//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation
import SwiftUI

@MainActor
protocol NativePlaybackEngine: AnyObject {
    var time: Duration { get }
    func open(
        _ request: NativePlaybackRequest,
        generation: UUID,
        receive: @escaping @MainActor (NativeObservation, UUID) -> Void
    )
    func seek(_ time: Duration, completion: @escaping @MainActor (Bool) -> Void)
    func play()
    func pause()
    func stop()
    func rate(_ value: Float)
    func aspectFill(_ value: Bool)
    func surface(showControls: Bool) -> AnyView
}

enum NativeObservation: Sendable, Equatable {
    case ready
    case failed
    case ended
    case clock(Duration)
    case state(NativePlaybackState)
}

/// AVPlayer lifecycle stays on one actor; all SDK callbacks carry the opened generation.
@MainActor
public final class NativePlaybackController {
    private let engine: any NativePlaybackEngine
    private var generation: UUID?
    private var start: Duration = .zero
    private var live = false
    private var prepared = false
    private var seeking = false
    private var seekRevision: UInt64 = 0
    private var wantsPlayback = true
    private var ended = false
    public var onEvent: (@MainActor (NativePlaybackEvent) -> Void)?

    public convenience init() {
        self.init(engine: AVPlaybackEngine())
    }

    init(engine: any NativePlaybackEngine) {
        self.engine = engine
    }

    isolated deinit { engine.stop() }

    public func open(_ request: NativePlaybackRequest) {
        stop()
        let generation = UUID()
        self.generation = generation
        start = request.live ? .zero : request.start
        live = request.live
        prepared = false
        seeking = false
        wantsPlayback = true
        ended = false
        engine.open(request, generation: generation) { [weak self] observation, callbackGeneration in
            self?.receive(observation, generation: callbackGeneration)
        }
    }

    public func play() {
        guard generation != nil, !ended else { return }
        wantsPlayback = true
        if prepared, !seeking {
            engine.play()
        }
    }

    public func pause() {
        guard generation != nil else { return }
        wantsPlayback = false
        engine.pause()
    }

    public func stop() {
        generation = nil
        prepared = false
        seeking = false
        seekRevision &+= 1
        engine.stop()
    }

    public func seek(_ time: Duration) {
        guard let generation, prepared, !ended else { return }
        performSeek(max(.zero, time), generation: generation, starting: false)
    }

    public func jump(_ offset: Duration) {
        guard generation != nil, prepared, !ended else { return }
        seek(max(.zero, engine.time + offset))
    }

    public func setRate(_ value: Float) {
        guard generation != nil, value.isFinite, value > 0 else { return }
        engine.rate(value)
    }

    public func setAspectFill(_ value: Bool) {
        engine.aspectFill(value)
    }

    public func surface(showControls: Bool = false) -> AnyView {
        engine.surface(showControls: showControls)
    }

    private func performSeek(_ time: Duration, generation: UUID, starting: Bool) {
        seekRevision &+= 1
        let revision = seekRevision
        seeking = true
        engine.seek(time) { [weak self] finished in
            guard let self, self.generation == generation, self.seekRevision == revision, self.seeking else { return }
            self.seeking = false
            guard finished else {
                if starting {
                    self.fail()
                }
                return
            }
            self.onEvent?(.resumePosition(time))
            // The event's host may synchronously stop/replace/pause this item.
            guard self.generation == generation, self.seekRevision == revision else { return }
            if self.wantsPlayback {
                self.engine.play()
            }
        }
    }

    private func receive(_ observation: NativeObservation, generation: UUID) {
        guard self.generation == generation, !ended else { return }
        switch observation {
        case .ready:
            guard !prepared else { return }
            prepared = true
            performSeek(start, generation: generation, starting: true)
        case .failed: fail()
        case let .clock(time):
            guard prepared, !seeking else { return }
            onEvent?(.clock(time))
        case let .state(state):
            guard prepared, !seeking else { return }
            switch state {
            case .playing: wantsPlayback = true
            case .paused: wantsPlayback = false
            case .waiting: break
            }
            onEvent?(.state(state))
        case .ended:
            guard !live, prepared, !seeking else { return }
            ended = true
            wantsPlayback = false
            onEvent?(.naturalEnd)
        }
    }

    private func fail() {
        stop()
        onEvent?(.playbackFailed)
    }
}
