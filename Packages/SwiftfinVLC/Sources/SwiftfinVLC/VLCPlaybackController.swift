//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Combine
import Foundation
import KidsDiagnostics
import SwiftUI

@MainActor
protocol VLCNativeEngine: AnyObject {
    var frame: VLCPlaybackFrame { get }
    var subtitleTracks: [VLCSubtitleTrack] { get }
    func surface(controller: VLCPlaybackController, generation: UUID) -> AnyView
    func observeUpdates(_ update: @escaping @MainActor () -> Void)
    func cancelUpdates()
    func open(_ request: VLCPlaybackRequest) throws
    func play() throws
    func pause()
    func stop()
    func seek(_ time: Duration) throws
    func jump(_ offset: Duration)
    func rate(_ value: Float) throws
    func audioTrack(_ index: Int?)
    func subtitleTrack(_ index: Int?)
    func aspectFill(_ value: Bool)
    func audioDelay(_ value: Duration) throws
    func subtitleDelay(_ value: Duration) throws
    func subtitleStyle(_ value: VLCSubtitleStyle)
    func shutdown() async -> Bool
}

enum VLCObservation { case clock, state, buffer, seekable, end, audioTracks, subtitleTracks }

/// Owns the SDK, renderer and native lifecycle; no SDK object escapes this module.
@MainActor
public final class VLCPlaybackController {
    private let engine: any VLCNativeEngine
    private let updateSubject = PassthroughSubject<Void, Never>()
    private var generation: UUID?
    private var request: VLCPlaybackRequest?
    private var pendingStart: Duration?
    private var buffering = false
    private var ended = false
    private var terminalPosition: Duration = .zero
    private var performance: KidsPerformanceSpan?
    private var performanceSampler: Task<Void, Never>?
    private var nativeDiagnostics: Task<Void, Never>?
    public var onEvent: (@MainActor (VLCPlaybackEvent) -> Void)?

    public convenience init() {
        self.init(engine: SwiftVLCNativeEngine())
    }

    init(engine: any VLCNativeEngine) {
        self.engine = engine
        engine.observeUpdates { [weak self] in
            guard let self, self.generation != nil else { return }
            self.updateSubject.send(())
        }
    }

    isolated deinit {
        performanceSampler?.cancel()
        nativeDiagnostics?.cancel()
        engine.cancelUpdates()
    }

    public var updates: AnyPublisher<Void, Never> {
        updateSubject.eraseToAnyPublisher()
    }

    public var frame: VLCPlaybackFrame {
        var result = engine.frame
        result.buffering = buffering
        result.applyingStartPosition = pendingStart != nil
        return result
    }

    public func surface(generation: UUID) -> AnyView {
        engine.surface(controller: self, generation: generation)
    }

    public func open(_ request: VLCPlaybackRequest, generation: UUID, performance: KidsPerformanceSpan? = nil) {
        self.generation = generation
        self.request = request
        self.performance = performance
        self.pendingStart = !request.live && request.start > .zero ? request.start : nil
        self.ended = false
        self.terminalPosition = .zero
        performanceSampler?.cancel()
        nativeDiagnostics?.cancel()
        do {
            nativeDiagnostics = SwiftVLCNativeEngine.observeDiagnostics(performance)
            performance?.mark(.vlcOpen, values: ["resume_seconds": request.start.vlcSeconds])
            try engine.open(request)
            performance?.mark(.vlcOpenReturned)
            observeStartup(generation: generation)
            engine.subtitleStyle(request.subtitleStyle)
        } catch {
            pendingStart = nil
            onEvent?(.playbackFailed)
        }
    }

    public func play() {
        guard generation != nil else { return }
        perform(.play) { try engine.play() }
    }

    public func pause() {
        guard generation != nil else { return }
        engine.pause()
    }

    public func stop() {
        generation = nil
        pendingStart = nil
        buffering = false
        performanceSampler?.cancel()
        nativeDiagnostics?.cancel()
        performanceSampler = nil
        nativeDiagnostics = nil
        engine.stop()
    }

    public func jump(_ offset: Duration) {
        guard generation != nil else { return }
        terminalPosition = .zero
        engine.jump(offset)
    }

    public func setRate(_ value: Float) {
        guard generation != nil else { return }
        perform(.rate) { try engine.rate(value) }
    }

    public func seek(_ value: Duration) {
        guard generation != nil, engine.frame.seekable else { return }
        pendingStart = nil
        perform(.seek) {
            try engine.seek(value)
            terminalPosition = max(.zero, value)
        }
    }

    public func setAudioTrack(_ index: Int?) {
        engine.audioTrack(index)
    }

    public func setSubtitleTrack(_ index: Int?) {
        engine.subtitleTrack(index)
    }

    public func setAspectFill(_ value: Bool) {
        engine.aspectFill(value)
    }

    public func setAudioDelay(_ value: Duration) {
        perform(.audioDelay) { try engine.audioDelay(value) }
    }

    public func setSubtitleDelay(_ value: Duration) {
        perform(.subtitleDelay) { try engine.subtitleDelay(value) }
    }

    public func setSubtitleStyle(_ value: VLCSubtitleStyle) {
        engine.subtitleStyle(value)
    }

    public func shutdown() async -> Bool {
        stop()
        engine.cancelUpdates()
        return await engine.shutdown()
    }

    private func perform(_ operation: VLCPlaybackOperation, _ action: () throws -> Void) {
        do { try action() } catch { onEvent?(.operationRejected(operation)) }
    }

    @discardableResult
    private func applyPendingStart() -> Bool {
        guard let pendingStart, engine.frame.seekable else { return false }
        self.pendingStart = nil
        performance?.once(.resumeSeek, values: ["seconds": pendingStart.vlcSeconds])
        do {
            try engine.seek(pendingStart)
            terminalPosition = pendingStart
            onEvent?(.resumePosition(pendingStart))
        } catch { onEvent?(.operationRejected(.seek)) }
        return true
    }

    func observed(_ kind: VLCObservation, generation: UUID) {
        guard self.generation == generation else { return }
        let native = engine.frame
        switch kind {
        case .clock:
            guard native.state == .playing || native.state == .paused, !applyPendingStart() else { return }
            terminalPosition = max(.zero, native.time)
            if native.time.vlcSeconds > (request?.start.vlcSeconds ?? 0) + 0.1 {
                performance?.once(.firstClock, values: ["seconds": native.time.vlcSeconds])
            }
            if native.state == .playing {
                buffering = false
            }
            onEvent?(.clock(frame))
        case .state:
            switch native.state {
            case .opening: performance?.once(.vlcOpening)
                buffering = true
            case .buffering: performance?.once(.vlcBuffering)
                buffering = true
            case .playing: performance?.once(.vlcPlaying)
                applyPendingStart()
                buffering = false
            case .paused: buffering = false
            case .error: performance?.once(.playerError)
                performance?.finish(.failure)
                buffering = false
            case .idle, .stopped, .stopping: break
            }
            onEvent?(.state(frame))
        case .buffer:
            guard native.state == .playing else { return }
            if native.bufferFill < 0.9 {
                buffering = true
            } else if native.bufferFill >= 1 {
                buffering = false
            }
            onEvent?(.buffer(frame))
        case .seekable: applyPendingStart()
        case .end:
            guard native.reachedEnd, request?.live == false, !ended else { return }
            ended = true
            buffering = false
            // SwiftVLC resets its clock when stopping. Keep the latest clock/accepted
            // seek, but do not turn an early stream termination into watched progress.
            let position = max(native.time, terminalPosition)
            if let runtime = request?.runtime, runtime > .zero,
               position < max(.zero, runtime - .seconds(5))
            {
                performance?.once(.playerError, values: ["seconds": position.vlcSeconds, "runtime_seconds": runtime.vlcSeconds])
                performance?.finish(.failure)
                onEvent?(.playbackFailed)
            } else {
                onEvent?(.naturalEnd(request?.runtime))
            }
        case .audioTracks: onEvent?(.audioTracksChanged)
        case .subtitleTracks: onEvent?(.subtitleTracksChanged(engine.subtitleTracks))
        }
    }

    private func observeStartup(generation: UUID) {
        guard let performance else { return }
        performanceSampler = Task { [weak self] in
            for _ in 0 ..< 400 {
                guard !Task.isCancelled, let self, self.generation == generation else { return }
                let sample = self.engine.frame
                let values: [String: Double] = [
                    "read_bytes": Double(sample.readBytes), "decoded_video": Double(sample.decodedVideo),
                    "displayed_pictures": Double(sample.displayedPictures), "lost_pictures": Double(sample.lostPictures),
                    "resume_pending": self.pendingStart == nil ? 0 : 1
                ]
                if sample.readBytes > 0 {
                    performance.once(.firstInput, values: values)
                }
                if sample.decodedVideo > 0 {
                    performance.once(.firstDecode, values: values)
                }
                if sample.displayedPictures > 0 {
                    performance.once(.firstVideoOutput, values: values)
                    performance.finish()
                    return
                }
                try? await Task.sleep(for: .milliseconds(50))
            }
            guard !Task.isCancelled, let self, self.generation == generation else { return }
            let sample = self.engine.frame
            performance.once(.observationTimeout, values: [
                "read_bytes": Double(sample.readBytes), "decoded_video": Double(sample.decodedVideo),
                "displayed_pictures": Double(sample.displayedPictures), "lost_pictures": Double(sample.lostPictures)
            ])
        }
    }
}
