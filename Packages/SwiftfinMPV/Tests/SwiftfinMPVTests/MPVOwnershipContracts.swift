//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation
import MPVUI
@testable import SwiftfinMPV
import SwiftUI
import Testing

@MainActor
private final class FakeEngine: MPVNativeEngine {
    struct Observation { let frame: @MainActor (MPVPlaybackFrame) -> Void
        let subtitle: @MainActor (TextSubtitleSnapshot) -> Void
    }

    var frame = MPVPlaybackFrame()
    var observations: [Observation] = []
    var requests: [MPVPlaybackRequest] = []
    var commands: [String] = []
    var seeks: [Duration] = []
    var rates: [Float] = []
    var delays: [Duration] = []
    var selected: [MPVPlaybackTrack] = []
    var disabled: [MPVPlaybackTrackKind] = []
    var sidecars: [(URL, String)] = []
    var surfaces = 0
    func open(_ request: MPVPlaybackRequest) {
        commands.append("open")
        requests.append(request)
        frame = MPVPlaybackFrame()
        frame.sourceURL = request.url
        frame.phase = .loading
        frame.time = request.start ?? .zero
    }

    func observe(frame: @escaping @MainActor (MPVPlaybackFrame) -> Void, subtitle: @escaping @MainActor (TextSubtitleSnapshot) -> Void) {
        commands.append("observe")
        observations.append(.init(frame: frame, subtitle: subtitle))
    }

    func cancelUpdates() {
        commands.append("cancel")
    }

    func surface() -> AnyView {
        surfaces += 1
        return AnyView(EmptyView())
    }

    func play() {
        commands.append("play")
    }

    func pause() {
        commands.append("pause")
    }

    func stop() {
        commands.append("stop")
    }

    func seek(_ time: Duration) {
        seeks.append(time)
    }

    func rate(_ value: Float) {
        rates.append(value)
    }

    func selectTrack(_ track: MPVPlaybackTrack) {
        selected.append(track)
    }

    func disableTrack(_ kind: MPVPlaybackTrackKind) {
        disabled.append(kind)
    }

    func aspectFill(_ value: Bool) {
        commands.append(value ? "fill" : "fit")
    }

    func audioDelay(_ value: Duration) {
        delays.append(value)
    }

    func subtitleDelay(_ value: Duration) {
        delays.append(value)
    }

    func addSubtitle(url: URL, title: String) {
        sidecars.append((url, title))
    }

    func emit(
        _ phase: MPVPlaybackPhase,
        time: Duration = .zero,
        source: URL? = nil,
        tracks: [MPVPlaybackTrack] = [],
        at index: Int? = nil
    ) {
        var value = frame
        value.phase = phase
        value.time = time
        value.sourceURL = source ?? frame.sourceURL
        value.tracks = tracks
        frame = value
        observations[index ?? (observations.count - 1)].frame(value)
    }

    func caption(_ text: String, at index: Int? = nil) {
        observations[index ?? (observations.count - 1)].subtitle(.init(regions: [.init(text: text)]))
    }
}

@MainActor
struct MPVOwnershipContracts {
    private let url = URL(string: "https://synthetic.invalid/video?token=PRIVATE")!
    private func request(start: Duration? = .seconds(9), sidecars: [MPVSidecarSubtitle] = []) -> MPVPlaybackRequest {
        .init(url: url, start: start, autoPlay: false, rate: 1.25, sidecars: sidecars)
    }

    private func settle() async {
        for _ in 0 ..< 30 {
            await Task.yield()
        }
    }

    @Test
    func `opening retains exact options normalizes only negative resume and redacts descriptions`() {
        let engine = FakeEngine()
        let controller = MPVPlaybackController(engine: engine)
        let id = UUID()
        controller.open(request(), generation: id)
        #expect(engine.commands == ["cancel", "open", "observe"])
        #expect(engine.requests.first?.start == .seconds(9) && engine.requests.first?.autoPlay == false && engine.requests.first?
            .rate == 1.25)
        #expect(controller.isCurrent(id) && controller.frame.sourceURL == url)
        #expect(request(start: .seconds(-2)).start == .zero && request(start: nil).start == nil)
        #expect(!String(describing: request()).contains("PRIVATE") && !String(reflecting: request()).contains("synthetic"))
        #expect(!String(describing: controller.frame).contains("PRIVATE"))
    }

    @Test
    func `old callbacks are rejected even when a new generation reuses the exact URL`() {
        let engine = FakeEngine()
        let controller = MPVPlaybackController(engine: engine)
        var events: [UUID] = []
        controller.onFrame = { id, _ in events.append(id) }
        let old = UUID()
        let new = UUID()
        controller.open(request(), generation: old)
        engine.emit(.playing, time: .seconds(10))
        controller.open(request(), generation: new)
        let before = controller.frame
        engine.emit(.ended, time: .seconds(99), at: 0)
        #expect(controller.frame == before && events == [old])
        engine.emit(.paused, time: .seconds(11), at: 1)
        #expect(controller.frame.time == .seconds(11) && events == [old, new])
    }

    @Test
    func `wrong source frames cannot publish through the active callback`() {
        let engine = FakeEngine()
        let controller = MPVPlaybackController(engine: engine)
        controller.open(request(), generation: UUID())
        let before = controller.frame
        engine.emit(.playing, time: .seconds(22), source: url.appending(queryItems: [.init(name: "source", value: "different")]))
        #expect(controller.frame == before)
    }

    @Test
    func `stop rejects delayed events clears sensitive source and suppresses inactive commands`() {
        let engine = FakeEngine()
        let controller = MPVPlaybackController(engine: engine)
        let id = UUID()
        controller.open(request(), generation: id)
        controller.stop()
        controller.stop()
        controller.play()
        controller.pause()
        controller.seek(.seconds(4))
        controller.jump(.seconds(2))
        controller.setRate(2)
        controller.setAspectFill(true)
        controller.setAudioDelay(.seconds(1))
        controller.setSubtitleDelay(.seconds(1))
        controller.setTrack(1, kind: .audio)
        engine.emit(.playing, time: .seconds(88), at: 0)
        #expect(!controller.isCurrent(id) && controller.frame.phase == .stopped && controller.frame.sourceURL == nil)
        #expect(engine.commands.filter { $0 == "stop" }.count == 1 && engine.seeks.isEmpty && engine.rates.isEmpty && engine.selected
            .isEmpty)
    }

    @Test
    func `transport commands retain absolute and relative positions rate aspect and signed delays`() {
        let engine = FakeEngine()
        let controller = MPVPlaybackController(engine: engine)
        controller.open(request(), generation: UUID())
        engine.emit(.playing, time: .seconds(20))
        controller.play()
        controller.pause()
        controller.seek(.seconds(5))
        controller.jump(.seconds(-3))
        controller.setRate(1.75)
        controller.setAspectFill(true)
        controller.setAudioDelay(.milliseconds(-250))
        controller.setSubtitleDelay(.seconds(2))
        #expect(engine.seeks == [.seconds(5), .seconds(17)] && engine.rates == [1.75])
        #expect(engine.delays == [.milliseconds(-250), .seconds(2)])
        #expect(engine.commands.suffix(3) == ["play", "pause", "fill"])
    }

    @Test
    func `track selection uses kind and native ID and preserves disable and no-op rules`() {
        let engine = FakeEngine()
        let controller = MPVPlaybackController(engine: engine)
        controller.open(request(), generation: UUID())
        engine.emit(
            .ready,
            tracks: [.init(index: 1, kind: .audio, selected: true), .init(index: 1, kind: .subtitle), .init(index: 2, kind: .audio)]
        )
        controller.setTrack(1, kind: .audio)
        controller.setTrack(1, kind: .subtitle)
        controller.setTrack(9, kind: .audio)
        controller.setTrack(nil, kind: .audio)
        controller.setTrack(-1, kind: .subtitle)
        #expect(engine.selected == [.init(index: 1, kind: .subtitle)] && engine.disabled == [.audio])
    }

    @Test
    func `sidecar commands retain original order tags and one attempt per unmapped index`() throws {
        let engine = FakeEngine()
        let controller = MPVPlaybackController(engine: engine)
        let id = UUID()
        let a = try #require(URL(string: "https://synthetic.invalid/a"))
        let b = try #require(URL(string: "https://synthetic.invalid/b"))
        controller.open(
            request(sidecars: [
                .init(jellyfinIndex: nil, url: a),
                .init(jellyfinIndex: 1, url: a),
                .init(jellyfinIndex: 2, url: b),
                .init(jellyfinIndex: 2, url: a)
            ]),
            generation: id
        )
        controller.loadMissingSidecars(mappedIndexes: [], generation: id)
        #expect(engine.sidecars.isEmpty)
        engine.emit(.ready, tracks: [.init(index: 7, kind: .audio)])
        controller.loadMissingSidecars(mappedIndexes: [1], generation: id)
        controller.loadMissingSidecars(mappedIndexes: [1], generation: id)
        #expect(engine.sidecars.count == 1 && engine.sidecars[0].0 == b && engine.sidecars[0].1 == "swiftfin-subtitle-2")
        controller.loadMissingSidecars(mappedIndexes: [], generation: UUID())
        #expect(engine.sidecars.count == 1)
    }

    @Test
    func `loading and replacement reset sidecar attempts but terminal frames cannot attach subtitles`() {
        let engine = FakeEngine()
        let controller = MPVPlaybackController(engine: engine)
        let old = UUID()
        let new = UUID()
        let value = request(sidecars: [.init(jellyfinIndex: 3, url: url)])
        controller.open(value, generation: old)
        engine.emit(.playing, tracks: [.init(index: 1, kind: .audio)])
        controller.loadMissingSidecars(mappedIndexes: [], generation: old)
        engine.emit(.loading)
        engine.emit(.ready, tracks: [.init(index: 1, kind: .audio)])
        controller.loadMissingSidecars(mappedIndexes: [], generation: old)
        engine.emit(.ended, tracks: [.init(index: 1, kind: .audio)])
        controller.loadMissingSidecars(mappedIndexes: [], generation: old)
        #expect(engine.sidecars.count == 2)
        controller.open(value, generation: new)
        engine.emit(.ready, tracks: [.init(index: 1, kind: .audio)])
        controller.loadMissingSidecars(mappedIndexes: [], generation: old)
        controller.loadMissingSidecars(mappedIndexes: [], generation: new)
        #expect(engine.sidecars.count == 3)
    }

    @Test
    func `identical frame observations are coalesced while time and track changes still publish`() {
        let engine = FakeEngine()
        let controller = MPVPlaybackController(engine: engine)
        var count = 0
        controller.onFrame = { _, _ in count += 1 }
        controller.open(request(), generation: UUID())
        engine.emit(.ready)
        engine.emit(.ready)
        engine.emit(.ready, time: .seconds(1))
        engine.emit(.ready, time: .seconds(1), tracks: [.init(index: 1, kind: .audio)])
        #expect(count == 3)
    }

    @Test
    func `all SDK states retain their phase transient terminal and failure projections`() {
        let states: [(MPVPlaybackState, MPVPlaybackPhase)] = [
            (.idle, .idle),
            (.loading, .loading),
            (.ready, .ready),
            (.playing, .playing),
            (.paused, .paused),
            (.buffering, .buffering),
            (.seeking, .seeking),
            (.ended, .ended),
            (.stopped, .stopped),
            (.failed(.init(localizedDescription: "specific failure")), .failed(.init(message: "specific failure")))
        ]
        for (sdk, expected) in states {
            let projected = NativeMPVEngine.project(state: sdk, time: .seconds(1), information: .empty)
            #expect(projected.phase == expected && projected.phase.transient == sdk.isTransient)
            #expect(projected.videoSize == nil && projected.subtitleVideoSize == nil)
        }
        let error = MPVPlaybackFailure(message: "PRIVATE")
        #expect(error.errorDescription == "PRIVATE" && !String(describing: error).contains("PRIVATE") && !String(reflecting: error)
            .contains("PRIVATE"))
    }

    @Test
    func `pixel aspect rotation and native track fields retain original projection semantics`() {
        let information = MPVMediaInformation(
            sourceURL: url,
            dimensions: .init(width: 100, height: 80, displayWidth: 120),
            rotation: -90,
            tracks: [
                .init(id: 5, type: .subtitle, title: "named", isSelected: true, isExternal: true),
                .init(id: 1, type: .audio)
            ]
        )
        let value = NativeMPVEngine.project(state: .playing, time: .seconds(4), information: information)
        #expect(value.videoSize == CGSize(width: 120, height: 80) && value.subtitleVideoSize == CGSize(width: 80, height: 120))
        #expect(value.tracks == [
            .init(index: 5, kind: .subtitle, title: "named", external: true, selected: true),
            .init(index: 1, kind: .audio)
        ])
        let halfTurn = NativeMPVEngine.project(
            state: .ready,
            time: .zero,
            information: .init(dimensions: .init(width: 10, height: 20), rotation: 540)
        )
        #expect(halfTurn.subtitleVideoSize == CGSize(width: 10, height: 20))
    }

    @Test
    func `caption streams replay latest values finish on stop and reject old-generation emissions`() async {
        let engine = FakeEngine()
        let controller = MPVPlaybackController(engine: engine)
        let old = UUID()
        let new = UUID()
        controller.open(request(), generation: old)
        engine.caption("first")
        var iterator = controller.subtitles(generation: old).makeAsyncIterator()
        #expect(await iterator.next()?.text == "first")
        controller.open(request(), generation: new)
        engine.caption("late", at: 0)
        #expect(await iterator.next() == nil)
        var current = controller.subtitles(generation: new).makeAsyncIterator()
        #expect(await current.next()?.isEmpty == true)
        engine.caption("new")
        #expect(await current.next()?.text == "new")
        controller.stop()
        #expect(await current.next() == nil)
    }

    @Test
    func `presentation replacement rejects old buffered captions and prior cleanup cannot clear the new value`() async {
        let engine = FakeEngine()
        let controller = MPVPlaybackController(engine: engine)
        let presentation = MPVTextSubtitlePresentation()
        let a = UUID()
        let b = UUID()
        let first = Task { await presentation.observe(controller, generation: a) { controller.open(request(), generation: a) } }
        await settle()
        engine.caption("old")
        let second = Task { await presentation.observe(controller, generation: b) { controller.open(request(), generation: b) } }
        await settle()
        engine.caption("new")
        await settle()
        engine.caption("obsolete", at: 0)
        await settle()
        #expect(presentation.snapshot.text == "new")
        await first.value
        #expect(presentation.snapshot.text == "new")
        presentation.clear()
        await second.value
        #expect(presentation.snapshot.isEmpty)
    }

    @Test
    func `explicit clear ends a quiet caption reader and cancelled parent never opens a player`() async {
        let engine = FakeEngine()
        let controller = MPVPlaybackController(engine: engine)
        let presentation = MPVTextSubtitlePresentation()
        let id = UUID()
        let task = Task { await presentation.observe(controller, generation: id) { controller.open(request(), generation: id) } }
        await settle()
        presentation.clear()
        await task.value
        #expect(presentation.snapshot.isEmpty)
        let before = engine.requests.count
        let cancelled = Task {
            await presentation.observe(controller, generation: UUID()) { controller.open(request(), generation: UUID()) }
        }
        cancelled.cancel()
        await cancelled.value
        #expect(engine.requests.count == before)
    }

    @Test
    func `releasing the controller cancels observations without native callbacks retaining it`() {
        let engine = FakeEngine()
        var controller: MPVPlaybackController? = MPVPlaybackController(engine: engine)
        weak let weakController = controller
        controller?.open(request(), generation: UUID())
        controller = nil
        #expect(weakController == nil && engine.commands.last == "stop")
        engine.emit(.playing, at: 0)
    }

    @Test
    func `reopening with the same render identity still rejects the prior operation callbacks`() async {
        let engine = FakeEngine()
        let controller = MPVPlaybackController(engine: engine)
        let id = UUID()
        controller.open(request(), generation: id)
        engine.emit(.playing, time: .seconds(10))
        controller.open(request(), generation: id)
        let expected = controller.frame
        engine.emit(.ended, time: .seconds(99), at: 0)
        #expect(controller.frame == expected)
        engine.caption("late", at: 0)
        var captions = controller.subtitles(generation: id).makeAsyncIterator()
        #expect(await captions.next()?.isEmpty == true)
        engine.caption("new", at: 1)
        #expect(await captions.next()?.text == "new")
    }

    @Test
    func `reentrant stop from a frame observer retires all later callbacks`() {
        let engine = FakeEngine()
        let controller = MPVPlaybackController(engine: engine)
        controller.open(request(), generation: UUID())
        controller.onFrame = {
            _, value in if value.phase == .ready {
                controller.stop()
            }
        }
        engine.emit(.ready)
        engine.emit(.playing, time: .seconds(19), at: 0)
        #expect(controller.frame.phase == .stopped && controller.frame.sourceURL == nil)
        controller.onFrame = nil
    }

    @Test
    func `renderer construction reaches the engine only for the current active identity`() {
        let engine = FakeEngine()
        let controller = MPVPlaybackController(engine: engine)
        let old = UUID()
        let new = UUID()
        _ = controller.surfaceContent(generation: old)
        #expect(engine.surfaces == 0)
        controller.open(request(), generation: old)
        _ = controller.surfaceContent(generation: old)
        controller.open(request(), generation: new)
        _ = controller.surfaceContent(generation: old)
        _ = controller.surfaceContent(generation: new)
        controller.stop()
        _ = controller.surfaceContent(generation: new)
        #expect(engine.surfaces == 2)
    }

    @Test
    func `parent cancellation ends a quiet caption reader while playback remains owned by the controller`() async {
        let engine = FakeEngine()
        let controller = MPVPlaybackController(engine: engine)
        let presentation = MPVTextSubtitlePresentation()
        let id = UUID()
        let task = Task { await presentation.observe(controller, generation: id) { controller.open(request(), generation: id) } }
        await settle()
        task.cancel()
        await task.value
        #expect(presentation.snapshot.isEmpty && controller.isCurrent(id))
        controller.stop()
    }

    @Test
    func `native metadata value projection can run on an independent executor`() async {
        let information = MPVMediaInformation(sourceURL: url, dimensions: .init(width: 16, height: 9), rotation: 90)
        let value = await Task.detached { NativeMPVEngine.project(state: .ready, time: .seconds(4), information: information) }.value
        #expect(value.phase == .ready && value.time == .seconds(4) && value.subtitleVideoSize == CGSize(width: 9, height: 16))
    }

    @Test
    func `track commands use current native metadata before its queued publication`() {
        let engine = FakeEngine()
        let controller = MPVPlaybackController(engine: engine)
        controller.open(request(), generation: UUID())
        engine.emit(.ready, tracks: [.init(index: 1, kind: .audio)])
        engine.frame.tracks = [.init(index: 1, kind: .audio, selected: true)]
        controller.setTrack(1, kind: .audio)
        #expect(engine.selected.isEmpty)
        engine.frame.tracks = [.init(index: 2, kind: .audio)]
        controller.setTrack(2, kind: .audio)
        #expect(engine.selected == [.init(index: 2, kind: .audio)])
        engine.frame.tracks = [.init(index: 2, kind: .audio, selected: true)]
        controller.setTrack(nil, kind: .audio)
        #expect(engine.disabled == [.audio])
        engine.frame.tracks = [.init(index: 2, kind: .audio)]
        controller.setTrack(-1, kind: .audio)
        #expect(engine.disabled == [.audio])
        engine.frame.sourceURL = url.appendingPathComponent("different-source")
        engine.frame.tracks = [.init(index: 3, kind: .audio)]
        controller.setTrack(3, kind: .audio)
        #expect(engine.selected.count == 1)
    }

    @Test
    func `relative jumps read the current native clock before its queued publication`() {
        let engine = FakeEngine()
        let controller = MPVPlaybackController(engine: engine)
        controller.open(request(), generation: UUID())
        engine.emit(.playing, time: .seconds(20))
        engine.frame.time = .seconds(22)
        controller.jump(.seconds(3))
        #expect(engine.seeks == [.seconds(25)])
        engine.frame.sourceURL = url.appendingPathComponent("different-source")
        controller.jump(.seconds(3))
        #expect(engine.seeks.count == 1)
    }
}
