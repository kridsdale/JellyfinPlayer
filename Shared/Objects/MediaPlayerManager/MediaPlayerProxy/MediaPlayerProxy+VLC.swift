//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Defaults
import Foundation
import JellyfinAPI
import KidsDiagnostics
import SwiftfinFormatting
import SwiftfinMediaTracks
import SwiftfinText
import SwiftfinTime
import SwiftfinUIState
import SwiftfinVLC
import SwiftUI

/// Maps app-owned metadata, settings and manager actions onto the native library.
@MainActor
final class VLCMediaPlayerProxy: VideoMediaPlayerProxy,
MediaPlayerOffsetConfigurable, MediaPlayerSubtitleConfigurable {
    let isBuffering: PublishedBox<Bool> = .init(initialValue: false)
    let videoSize: PublishedBox<CGSize> = .init(initialValue: .zero)
    let droppedFrames: PublishedBox<Int> = .init(initialValue: 0)
    let corruptedFrames: PublishedBox<Int> = .init(initialValue: 0)
    let native = VLCPlaybackController()
    var performance: KidsPerformanceSpan?
    var isApplyingStartPosition: Bool {
        native.frame.applyingStartPosition
    }

    var onNaturalEnd: (() -> Void)?
    private var onClock: ((Duration) -> Void)?
    private weak var openedItem: MediaPlayerItem?
    var observers: [any MediaPlayerObserver] = [NowPlayableObserver()]
    weak var manager: MediaPlayerManager? {
        didSet { for var observer in observers {
            observer.manager = manager
        } }
    }

    init() {
        native.onEvent = { [weak self] event in self?.receive(event) }
    }

    private func receive(_ event: VLCPlaybackEvent) {
        guard let manager, manager.state != .stopped, manager.state != .error,
              let openedItem, manager.playbackItem === openedItem else { return }
        func updateMetrics(_ frame: VLCPlaybackFrame) {
            isBuffering.value = frame.buffering
            videoSize.value = frame.videoSize
            droppedFrames.value = Int(clamping: frame.lostPictures)
            corruptedFrames.value = Int(clamping: frame.corruptedPictures)
        }
        switch event {
        case let .clock(frame):
            updateMetrics(frame)
            onClock?(frame.time)
            manager.seconds = frame.time
        case let .state(frame):
            updateMetrics(frame)
            manager.logger.trace("Native VLC state updated: \(frame.state)")
            switch frame.state {
            case .error: manager.error(ErrorMessage("VLC player is unable to perform playback"))
            case .playing:
                manager.setPlaybackRequestStatus(status: .playing)
                setRate(manager.rate)
                openedItem.switchTrack(type: .audio, index: openedItem.selectedAudioStreamIndex)
                openedItem.switchTrack(type: .subtitle, index: openedItem.selectedSubtitleStreamIndex)
            case .paused: manager.setPlaybackRequestStatus(status: .paused)
            default: break
            }
        case let .buffer(frame): updateMetrics(frame)
        case let .resumePosition(time): manager.seconds = time
        case let .naturalEnd(runtime):
            if let runtime {
                manager.seconds = runtime
            }
            isBuffering.value = false
            if let onNaturalEnd {
                onNaturalEnd()
            } else {
                manager.ended()
            }
        case .audioTracksChanged:
            openedItem.switchTrack(type: .audio, index: openedItem.selectedAudioStreamIndex)
        case let .subtitleTracksChanged(tracks):
            openedItem.updateSubtitleTrackMapping(subtitleTracks: tracks.map { (playerIndex: $0.index, id: $0.id) })
        case .playbackFailed: manager.error(ErrorMessage("VLC player is unable to perform playback"))
        case let .operationRejected(operation):
            manager.logger.warning("Native VLC operation rejected", metadata: ["operation": "\(operation)"])
        }
    }

    func play() {
        native.play()
    }

    func pause() {
        native.pause()
    }

    func stop() {
        openedItem = nil
        onClock = nil
        isBuffering.value = false
        native.stop()
    }

    func jumpForward(_ seconds: Duration) {
        let target: Duration = if let runtime = manager?.item.runtime, let current = manager?.seconds {
            min(seconds, max(.zero, runtime - current))
        } else {
            seconds
        }
        guard target > .zero else { return }
        native.jump(target)
    }

    func jumpBackward(_ seconds: Duration) {
        native.jump(.zero - seconds)
    }

    func setRate(_ rate: Float) {
        native.setRate(rate)
    }

    func setSeconds(_ seconds: Duration) {
        native.seek(seconds)
    }

    func setAudioStream(_ stream: MediaStream) {
        native.setAudioTrack(stream.index)
    }

    func setSubtitleStream(_ stream: MediaStream) {
        native.setSubtitleTrack(stream.index)
    }

    func setAspectFill(_ value: Bool) {
        native.setAspectFill(value)
    }

    func setAudioOffset(_ seconds: Duration) {
        native.setAudioDelay(seconds)
    }

    func setSubtitleOffset(_ seconds: Duration) {
        native.setSubtitleDelay(seconds)
    }

    func setSubtitleConfiguration(_ configuration: SubtitleConfiguration) {
        native.setSubtitleStyle(configuration.vlcStyle)
    }

    private func open(_ item: MediaPlayerItem, generation: UUID, configuration: SubtitleConfiguration) {
        let start = max(
            .zero,
            (item.baseItem.startSeconds ?? .zero) -
                (onNaturalEnd == nil ? Duration.seconds(Defaults[.VideoPlayer.resumeOffset]) : .zero)
        )
        let subtitles = item.sidecarSubtitles.map(\.url)
        openedItem = item
        native.open(.init(
            url: item.url,
            start: start,
            runtime: item.baseItem.runtime,
            live: item.baseItem.isLiveStream,
            subtitleURLs: subtitles,
            subtitleStyle: configuration.vlcStyle
        ), generation: generation, performance: performance)
    }

    @ViewBuilder
    var videoPlayerBody: some View {
        VLCPlayerView(proxy: self)
    }

    private struct VLCPlayerView: View {
        @ObservedObject
        var proxy: VLCMediaPlayerProxy
        @EnvironmentObject
        private var manager: MediaPlayerManager
        var body: some View {
            if let item = manager.playbackItem, manager.state != .stopped {
                ItemSurface(proxy: proxy, item: item).id(ObjectIdentifier(item))
            }
        }
    }

    private struct ItemSurface: View {
        @ObservedObject
        var proxy: VLCMediaPlayerProxy
        let item: MediaPlayerItem
        @State
        private var generation = UUID()
        @Default(.VideoPlayer.Subtitle.configuration)
        private var subtitleConfiguration
        @EnvironmentObject
        private var manager: MediaPlayerManager
        @EnvironmentObject
        private var containerState: VideoPlayerContainerState
        var body: some View {
            proxy.native.surface(generation: generation)
                .task(id: ObjectIdentifier(item)) {
                    do {
                        for observer in proxy.observers {
                            try await (observer as? NowPlayableObserver)?.prepareForPlayback()
                        }
                        guard !Task.isCancelled, manager.state != .stopped, manager.state != .error,
                              manager.playbackItem === item else { return }
                        guard let connection = item.connection else { throw CancellationError() }
                        try connection.preparation.checkBinding()
                        let clockState = containerState
                        proxy.onClock = { [weak clockState] time in
                            guard let clockState, !clockState.isScrubbing else { return }
                            clockState.scrubbedSeconds.value = time
                        }
                        proxy.open(item, generation: generation, configuration: subtitleConfiguration)
                    } catch is CancellationError {
                    } catch {
                        guard !Task.isCancelled, manager.state != .stopped, manager.playbackItem === item else { return }
                        await manager.error(ErrorMessage("Audio session could not start"))
                    }
                }
                .onChange(of: manager.rate) { proxy.setRate(manager.rate) }
                .onChange(of: subtitleConfiguration) { proxy.setSubtitleConfiguration(subtitleConfiguration) }
        }
    }
}

private extension SubtitleConfiguration {
    var vlcStyle: VLCSubtitleStyle {
        .init(
            fontName: fontName,
            colorRGB: Int(color.hexString.prefix(6), radix: 16),
            approximatePoints: Double(25 - size)
        )
    }
}
