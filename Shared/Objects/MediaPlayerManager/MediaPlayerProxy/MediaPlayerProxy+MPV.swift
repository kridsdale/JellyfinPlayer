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
import SwiftfinMediaTracks
import SwiftfinMPV
import SwiftfinTime
import SwiftfinUIState
import SwiftUI

@MainActor
final class MPVMediaPlayerProxy: VideoMediaPlayerProxy, MediaPlayerOffsetConfigurable {
    let isBuffering: PublishedBox<Bool> = .init(initialValue: false)
    let videoSize: PublishedBox<CGSize> = .init(initialValue: .zero)
    // The pinned SDK does not expose frame statistics.
    let droppedFrames: PublishedBox<Int> = .init(initialValue: 0)
    let corruptedFrames: PublishedBox<Int> = .init(initialValue: 0)
    let native = MPVPlaybackController()
    private weak var openedItem: MediaPlayerItem?
    private var generation: UUID?
    private var onClock: ((Duration) -> Void)?
    private var previousPhase: MPVPlaybackPhase = .idle
    private var previousTracks: [MPVPlaybackTrack] = []
    private var previousTime: Duration?
    var observers: [any MediaPlayerObserver] = [NowPlayableObserver()]
    weak var manager: MediaPlayerManager? {
        didSet { for var observer in observers {
            observer.manager = manager
        } }
    }

    init() {
        native.onFrame = { [weak self] id, frame in self?.receive(frame, generation: id) }
    }

    func play() {
        native.play()
    }

    func pause() {
        native.pause()
    }

    func stop() {
        generation = nil
        openedItem = nil
        onClock = nil
        previousTime = nil
        isBuffering.value = false
        native.stop()
    }

    func jumpForward(_ seconds: Duration) {
        native.jump(seconds)
    }

    func jumpBackward(_ seconds: Duration) {
        native.jump(.zero - seconds)
    }

    func setSeconds(_ seconds: Duration) {
        native.seek(seconds)
    }

    func setRate(_ rate: Float) {
        native.setRate(rate)
    }

    func setAudioStream(_ stream: MediaStream) {
        native.setTrack(stream.index, kind: .audio)
    }

    func setSubtitleStream(_ stream: MediaStream) {
        native.setTrack(stream.index, kind: .subtitle)
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

    private func receive(_ frame: MPVPlaybackFrame, generation: UUID) {
        guard self.generation == generation, native.isCurrent(generation), let manager,
              manager.state != .stopped, manager.state != .error, let item = openedItem,
              manager.playbackItem === item, frame.sourceURL == item.url else { return }
        isBuffering.value = frame.phase.transient
        videoSize.value = frame.videoSize ?? .zero
        if previousTime != frame.time || frame.phase == .ended {
            previousTime = frame.time
            onClock?(frame.time)
            manager.seconds = frame.time
        }
        let oldPhase = previousPhase
        previousPhase = frame.phase
        if oldPhase != frame.phase {
            switch frame.phase {
            case .playing: manager.setPlaybackRequestStatus(status: .playing)
            case .paused: manager.setPlaybackRequestStatus(status: .paused)
            case .ended:
                if !item.baseItem.isLiveStream {
                    manager.ended()
                }
            case let .failed(error): manager.error(error)
            default: break
            }
        }
        let tracksChanged = previousTracks != frame.tracks
        previousTracks = frame.tracks
        let readyChanged = oldPhase != frame.phase && (frame.phase == .ready || frame.phase == .playing || frame.phase == .paused)
        guard readyChanged || tracksChanged, native.isCurrent(generation), manager.playbackItem === item,
              frame.phase.acceptsTracks, !frame.tracks.isEmpty else { return }
        let tracks = frame.tracks.map { track -> CategorizedMediaTrack in
            let type: MediaStreamType = switch track.kind { case .video: .video
            case .audio: .audio
            case .subtitle: .subtitle }
            return .init(index: track.index, type: type, title: track.title, external: track.external)
        }
        let map = MediaTrackIndexMap.categorized(
            mediaStreams: item.mediaSource.mediaStreams ?? [],
            tracks: tracks,
            isTranscoding: item.mediaSource.transcodingURL != nil,
            selectedAudioStreamIndex: item.selectedAudioStreamIndex
        )
        item.setTrackIndexes(map)
        let mapped = Set(item.sidecarSubtitles.compactMap { subtitle -> Int? in
            guard let index = subtitle.jellyfinIndex, map.playerIndex(for: index) != nil else { return nil }
            return index
        })
        native.loadMissingSidecars(mappedIndexes: mapped, generation: generation)
    }

    private func open(_ item: MediaPlayerItem, generation: UUID) {
        // A caption/view-task reattachment must not restart the same active item.
        guard openedItem !== item || self.generation != generation || !native.isCurrent(generation) else { return }
        openedItem = item
        self.generation = generation
        previousPhase = .loading
        previousTracks = []
        previousTime = nil
        item.setTrackIndexes(.init())
        isBuffering.value = true
        let start = max(.zero, (item.baseItem.startSeconds ?? .zero) - .seconds(Defaults[.VideoPlayer.resumeOffset]))
        native.open(
            .init(
                url: item.url,
                start: item.baseItem.isLiveStream ? nil : start,
                autoPlay: manager?.playbackRequestStatus == .playing,
                rate: manager?.rate ?? 1,
                sidecars: item.sidecarSubtitles.map { .init(jellyfinIndex: $0.jellyfinIndex, url: $0.url) }
            ),
            generation: generation
        )
    }

    var videoPlayerBody: some View {
        PlayerView(proxy: self)
    }

    private struct PlayerView: View {
        @ObservedObject
        var proxy: MPVMediaPlayerProxy
        @EnvironmentObject
        private var manager: MediaPlayerManager
        var body: some View {
            if let item = manager.playbackItem,
               manager.state != .stopped
            {
                ItemSurface(proxy: proxy, item: item).id(ObjectIdentifier(item))
            }
        }
    }

    private struct ItemSurface: View {
        @ObservedObject
        var proxy: MPVMediaPlayerProxy
        let item: MediaPlayerItem
        @State
        private var generation = UUID()
        @State
        private var textSubtitles = MPVTextSubtitlePresentation()
        @EnvironmentObject
        private var manager: MediaPlayerManager
        @EnvironmentObject
        private var containerState: VideoPlayerContainerState
        var body: some View {
            proxy.native.surface(generation: generation)
                .overlay { TextSubtitleOverlay(
                    snapshot: textSubtitles.snapshot,
                    videoSize: proxy.native.frame.subtitleVideoSize,
                    isAspectFilled: containerState.isAspectFilled
                ) }
                .task(id: ObjectIdentifier(item)) {
                    guard !Task.isCancelled, manager.state != .stopped, manager.state != .error,
                          manager.playbackItem === item else { return }
                    let state = containerState
                    proxy.onClock = { [weak state] time in
                        guard let state, !state.isScrubbing else { return }
                        state.scrubbedSeconds.value = time
                    }
                    await textSubtitles.observe(proxy.native, generation: generation) { proxy.open(item, generation: generation) }
                }
                .onDisappear { textSubtitles.clear() }
                .onChange(of: manager.rate) { proxy.setRate(manager.rate) }
        }
    }
}
