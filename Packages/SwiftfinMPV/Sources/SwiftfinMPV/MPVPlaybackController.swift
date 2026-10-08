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

@MainActor
protocol MPVNativeEngine: AnyObject {
    var frame: MPVPlaybackFrame { get }
    func open(_ request: MPVPlaybackRequest)
    func observe(frame: @escaping @MainActor (MPVPlaybackFrame) -> Void, subtitle: @escaping @MainActor (TextSubtitleSnapshot) -> Void)
    func cancelUpdates()
    func surface() -> AnyView
    func play()
    func pause()
    func stop()
    func seek(_ time: Duration)
    func rate(_ value: Float)
    func selectTrack(_ track: MPVPlaybackTrack)
    func disableTrack(_ kind: MPVPlaybackTrackKind)
    func aspectFill(_ value: Bool)
    func audioDelay(_ value: Duration)
    func subtitleDelay(_ value: Duration)
    func addSubtitle(url: URL, title: String)
}

/// Main-actor owner of the native player, generation, observations and typed commands.
@MainActor
@Observable
public final class MPVPlaybackController {
    @ObservationIgnored
    private let engine: any MPVNativeEngine
    private var generation: UUID?
    @ObservationIgnored
    private var operationID: UUID?
    @ObservationIgnored
    private var request: MPVPlaybackRequest?
    @ObservationIgnored
    private var loadedSidecars: Set<Int> = []
    @ObservationIgnored
    private var captions: [UUID: [UUID: AsyncStream<TextSubtitleSnapshot>.Continuation]] = [:]
    @ObservationIgnored
    private var lastCaption = TextSubtitleSnapshot()
    public private(set) var frame = MPVPlaybackFrame()
    @ObservationIgnored
    public var onFrame: (@MainActor (UUID, MPVPlaybackFrame) -> Void)?

    public convenience init() {
        self.init(engine: NativeMPVEngine())
    }

    init(engine: any MPVNativeEngine) {
        self.engine = engine
    }

    isolated deinit {
        engine.cancelUpdates()
        if generation != nil {
            engine.stop()
        }
        for subscribers in captions.values {
            for continuation in subscribers.values {
                continuation.finish()
            }
        }
    }

    public func isCurrent(_ generation: UUID) -> Bool {
        self.generation == generation
    }

    public func open(_ request: MPVPlaybackRequest, generation: UUID) {
        engine.cancelUpdates()
        finishCaptions(except: generation)
        self.generation = generation
        let operation = UUID()
        operationID = operation
        self.request = request
        loadedSidecars.removeAll()
        lastCaption = TextSubtitleSnapshot()
        var opening = MPVPlaybackFrame()
        opening.phase = .loading
        opening.sourceURL = request.url
        opening.time = request.start ?? .zero
        frame = opening
        engine.open(request)
        engine.observe(
            frame: { [weak self] value in self?.receive(value, generation: generation, operation: operation) },
            subtitle: { [weak self] value in
                self?.receiveCaption(value, generation: generation, operation: operation)
            }
        )
        receive(engine.frame, generation: generation, operation: operation)
    }

    private func receive(_ value: MPVPlaybackFrame, generation: UUID, operation: UUID) {
        guard operationID == operation, isCurrent(generation), value.sourceURL == request?.url, frame != value else { return }
        if value.phase == .loading {
            loadedSidecars.removeAll()
        }
        frame = value
        onFrame?(generation, value)
    }

    private func receiveCaption(_ value: TextSubtitleSnapshot, generation: UUID, operation: UUID) {
        guard operationID == operation, isCurrent(generation) else { return }
        lastCaption = value
        for continuation in captions[generation]?.values ?? [:].values {
            continuation.yield(value)
        }
    }

    /// The sole public SDK interoperability value is its immutable semantic-caption snapshot.
    /// The player, native tracks, observation callbacks and command strings stay internal.
    public func subtitles(generation: UUID) -> AsyncStream<TextSubtitleSnapshot> {
        let id = UUID()
        let (stream, continuation) = AsyncStream<TextSubtitleSnapshot>.makeStream(bufferingPolicy: .bufferingNewest(1))
        captions[generation, default: [:]][id] = continuation
        continuation.yield(isCurrent(generation) ? lastCaption : TextSubtitleSnapshot())
        continuation.onTermination = { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.captions[generation]?[id] = nil
                if self?.captions[generation]?.isEmpty == true {
                    self?.captions[generation] = nil
                }
            }
        }
        return stream
    }

    private func finishCaptions(except generation: UUID? = nil) {
        for key in Array(captions.keys) where key != generation {
            let subscribers = captions.removeValue(forKey: key)
            for continuation in subscribers?.values ?? [:].values {
                continuation.finish()
            }
        }
    }

    public func stop() {
        let wasActive = generation != nil
        generation = nil
        operationID = nil
        request = nil
        engine.cancelUpdates()
        loadedSidecars.removeAll()
        lastCaption = TextSubtitleSnapshot()
        finishCaptions()
        frame = MPVPlaybackFrame()
        frame.phase = .stopped
        if wasActive {
            engine.stop()
        }
    }

    public func play() {
        guard generation != nil else { return }
        engine.play()
    }

    public func pause() {
        guard generation != nil else { return }
        engine.pause()
    }

    public func seek(_ time: Duration) {
        guard generation != nil else { return }
        engine.seek(time)
    }

    private var currentNativeFrame: MPVPlaybackFrame? {
        guard generation != nil, let request else { return nil }
        let value = engine.frame
        return value.sourceURL == request.url ? value : nil
    }

    public func jump(_ offset: Duration) {
        guard let value = currentNativeFrame else { return }
        engine.seek(value.time + offset)
    }

    public func setRate(_ value: Float) {
        guard generation != nil else { return }
        engine.rate(value)
    }

    public func setAspectFill(_ value: Bool) {
        guard generation != nil else { return }
        engine.aspectFill(value)
    }

    public func setAudioDelay(_ value: Duration) {
        guard generation != nil else { return }
        engine.audioDelay(value)
    }

    public func setSubtitleDelay(_ value: Duration) {
        guard generation != nil else { return }
        engine.subtitleDelay(value)
    }

    public func setTrack(_ index: Int?, kind: MPVPlaybackTrackKind) {
        guard let value = currentNativeFrame else { return }
        let tracks = value.tracks.filter { $0.kind == kind }
        guard let index, index >= 0 else {
            if tracks.contains(where: \.selected) {
                engine.disableTrack(kind)
            }
            return
        }
        if let track = tracks.first(where: { $0.index == index }), !track.selected {
            engine.selectTrack(track)
        }
    }

    public func loadMissingSidecars(mappedIndexes: Set<Int>, generation: UUID) {
        guard let operation = operationID, isCurrent(generation), frame.phase.acceptsTracks, !frame.tracks.isEmpty, let request,
              frame.sourceURL == request.url else { return }
        for sidecar in request.sidecars {
            // A native/frame callback may reopen the same rendering identity.
            guard operationID == operation, isCurrent(generation) else { return }
            guard let index = sidecar.jellyfinIndex, !mappedIndexes.contains(index), loadedSidecars.insert(index).inserted else { continue }
            engine.addSubtitle(url: sidecar.url, title: "swiftfin-subtitle-\(index)")
        }
    }

    public func surface(generation: UUID) -> AnyView {
        AnyView(Renderer(controller: self, generation: generation))
    }

    func surfaceContent(generation: UUID) -> AnyView {
        guard isCurrent(generation) else { return AnyView(EmptyView()) }
        return engine.surface()
    }

    private struct Renderer: View {
        let controller: MPVPlaybackController
        let generation: UUID
        var body: some View {
            controller.surfaceContent(generation: generation)
        }
    }
}
