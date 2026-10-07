//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation
import MPVUI
import Observation
import SwiftUI

/// Contains every raw MPVUI player/track/render/command interaction.
@MainActor
final class NativeMPVEngine: MPVNativeEngine {
    private let player = MPVPlayer()
    private var observationID: UUID?
    private var frameAction: (@MainActor (MPVPlaybackFrame) -> Void)?
    private var subtitleAction: (@MainActor (TextSubtitleSnapshot) -> Void)?
    private var subtitleStream: AsyncStream<TextSubtitleSnapshot>?
    private var subtitleTask: Task<Void, Never>?

    var frame: MPVPlaybackFrame {
        Self.project(state: player.state, time: player.position, information: player.mediaInformation)
    }

    func open(_ request: MPVPlaybackRequest) {
        // Opt into text interception before load to avoid a transient native text cue.
        subtitleStream = player.textSubtitleStream()
        player.load(request.url, autoPlay: request.autoPlay, startTime: request.start)
        player.setPlaybackRate(Double(request.rate))
        player.setProperty("panscan", to: "0")
    }

    func observe(frame: @escaping @MainActor (MPVPlaybackFrame) -> Void, subtitle: @escaping @MainActor (TextSubtitleSnapshot) -> Void) {
        cancelUpdates()
        let id = UUID()
        observationID = id
        frameAction = frame
        subtitleAction = subtitle
        arm(id)
        if let stream = subtitleStream {
            subtitleTask = Task { @MainActor [weak self] in
                for await snapshot in stream {
                    guard !Task.isCancelled, let self, self.observationID == id else { return }
                    self.subtitleAction?(snapshot)
                }
            }
        }
    }

    private func arm(_ id: UUID) {
        guard observationID == id else { return }
        withObservationTracking {
            _ = player.state
            _ = player.position
            _ = player.mediaInformation
        } onChange: { [weak self] in
            // Observation's callback has no actor annotation and runs before mutation commits.
            Task { @MainActor [weak self] in
                guard let self, self.observationID == id else { return }
                self.arm(id)
                self.frameAction?(self.frame)
            }
        }
    }

    func cancelUpdates() {
        observationID = nil
        frameAction = nil
        subtitleAction = nil
        subtitleTask?.cancel()
        subtitleTask = nil
    }

    isolated deinit { subtitleTask?.cancel() }
    func surface() -> AnyView {
        AnyView(MPVVideoPlayer(player: player))
    }

    func play() {
        player.play()
    }

    func pause() {
        player.pause()
    }

    func stop() {
        player.stop()
    }

    func seek(_ time: Duration) {
        player.seek(to: time)
    }

    func rate(_ value: Float) {
        player.setPlaybackRate(Double(value))
    }

    func selectTrack(_ track: MPVPlaybackTrack) {
        guard let value = player.mediaInformation.tracks.first(where: { $0.mpvID == track.index && Self.kind($0.type) == track.kind })
        else { return }
        player.selectTrack(value)
    }

    func disableTrack(_ kind: MPVPlaybackTrackKind) {
        switch kind { case .video: player.disableTrack(.video)
        case .audio: player.disableTrack(.audio)
        case .subtitle: player.disableTrack(.subtitle) }
    }

    func aspectFill(_ value: Bool) {
        player.setProperty("panscan", to: value ? "1" : "0")
    }

    func audioDelay(_ value: Duration) {
        player.setAudioDelay(value)
    }

    func subtitleDelay(_ value: Duration) {
        player.setSubtitleDelay(value)
    }

    func addSubtitle(url: URL, title: String) {
        player.command("sub-add", arguments: [url.absoluteString, "auto", title])
    }

    nonisolated static func kind(_ kind: MPVTrackType) -> MPVPlaybackTrackKind {
        switch kind { case .video: .video
        case .audio: .audio
        case .subtitle: .subtitle }
    }

    nonisolated static func project(state: MPVPlaybackState, time: Duration, information: MPVMediaInformation) -> MPVPlaybackFrame {
        var frame = MPVPlaybackFrame()
        switch state {
        case .idle: frame.phase = .idle
        case .loading: frame.phase = .loading
        case .ready: frame.phase = .ready
        case .playing: frame.phase = .playing
        case .paused: frame.phase = .paused
        case .buffering: frame.phase = .buffering
        case .seeking: frame.phase = .seeking
        case .ended: frame.phase = .ended
        case .stopped: frame.phase = .stopped
        case let .failed(error): frame.phase = .failed(.init(message: error.localizedDescription))
        }
        frame.time = time
        frame.sourceURL = information.sourceURL
        if let dimensions = information.dimensions {
            frame.videoSize = CGSize(width: dimensions.effectiveWidth, height: dimensions.effectiveHeight)
            var width = dimensions.effectiveWidth
            var height = dimensions.effectiveHeight
            let rotation = ((information.rotation % 360) + 360) % 360
            if rotation == 90 || rotation == 270 {
                swap(&width, &height)
            }
            frame.subtitleVideoSize = CGSize(width: width, height: height)
        }
        frame.tracks = information.tracks.map { .init(
            index: $0.mpvID,
            kind: kind($0.type),
            title: $0.title,
            external: $0.isExternal,
            selected: $0.isSelected
        ) }
        return frame
    }
}
