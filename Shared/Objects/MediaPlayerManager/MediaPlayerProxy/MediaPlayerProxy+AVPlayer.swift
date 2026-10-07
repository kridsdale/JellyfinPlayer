//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Combine
import Defaults
import Foundation
import JellyfinAPI
import SwiftfinFormatting
import SwiftfinNativePlayback
import SwiftfinText
import SwiftfinTime
import SwiftfinUIState
import SwiftUI

/// App composition maps the authorized item and current policy to the native owner.
@MainActor
final class AVMediaPlayerProxy: VideoMediaPlayerProxy {
    let native = NativePlaybackController()
    let isBuffering: PublishedBox<Bool> = .init(initialValue: false)
    var isScrubbing: Binding<Bool> = .constant(false)
    var scrubbedSeconds: Binding<Duration> = .constant(.zero)
    let videoSize: PublishedBox<CGSize> = .init(initialValue: .zero)
    let droppedFrames: PublishedBox<Int> = .init(initialValue: 0)
    let corruptedFrames: PublishedBox<Int> = .init(initialValue: 0)
    private weak var openedItem: MediaPlayerItem?
    private var itemObservation: AnyCancellable?
    private var stateObservation: AnyCancellable?
    var observers: [any MediaPlayerObserver] = [NowPlayableObserver()]
    weak var manager: MediaPlayerManager? {
        didSet {
            itemObservation?.cancel()
            stateObservation?.cancel()
            stop()
            for var observer in observers {
                observer.manager = manager
            }
            guard let manager else { return }
            itemObservation = manager.$playbackItem.sink { [weak self] item in
                guard let item else { self?.stop()
                    return
                }
                self?.open(item)
            }
            stateObservation = manager.$state.sink { [weak self] state in
                if state == .stopped || state == .error {
                    self?.stop()
                }
            }
        }
    }

    init() {
        native.onEvent = { [weak self] event in self?.receive(event) }
    }

    private func open(_ item: MediaPlayerItem) {
        let base = item.baseItem
        let episodeSeries = base.type == .episode ? base.seriesName : nil
        let start = max(.zero, (base.startSeconds ?? .zero) - .seconds(Defaults[.VideoPlayer.resumeOffset]))
        openedItem = item
        isBuffering.value = true
        native.open(.init(
            url: item.url,
            start: start,
            live: base.isLiveStream,
            title: episodeSeries ?? base.displayTitle,
            subtitle: episodeSeries == nil ? nil : base.displayTitle,
            overview: base.overview
        ))
    }

    private func receive(_ event: NativePlaybackEvent) {
        guard let manager, manager.state != .stopped, manager.state != .error,
              let openedItem, manager.playbackItem === openedItem else { return }
        switch event {
        case let .clock(time), let .resumePosition(time):
            if !isScrubbing.wrappedValue {
                scrubbedSeconds.wrappedValue = time
            }
            manager.seconds = time
        case let .state(state):
            isBuffering.value = state == .waiting
            switch state {
            case .playing: manager.setPlaybackRequestStatus(status: .playing)
            case .paused: manager.setPlaybackRequestStatus(status: .paused)
            case .waiting: break
            }
        case .naturalEnd:
            isBuffering.value = false
            if let runtime = openedItem.baseItem.runtime {
                manager.seconds = runtime
            }
            manager.ended()
        case .playbackFailed:
            isBuffering.value = false
            manager.error(ErrorMessage("Native player is unable to perform playback"))
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
        isBuffering.value = false
        native.stop()
    }

    func jumpForward(_ time: Duration) {
        native.jump(time)
    }

    func jumpBackward(_ time: Duration) {
        native.jump(.zero - time)
    }

    func setSeconds(_ time: Duration) {
        native.seek(time)
    }

    func setRate(_ rate: Float) {
        native.setRate(rate)
    }

    // Track selection remains the existing unsupported native-player feature.
    func setAudioStream(_: MediaStream) {}
    func setSubtitleStream(_: MediaStream) {}
    func setAspectFill(_ value: Bool) {
        native.setAspectFill(value)
    }

    var videoPlayerBody: some View {
        native.surface()
    }
}
