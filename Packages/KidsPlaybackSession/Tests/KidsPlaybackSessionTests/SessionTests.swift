//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Combine
import Foundation
import KidsDomain
@testable import KidsPlaybackSession
import Testing

@MainActor
private final class Driver: KidsPlaybackDriver {
    var frame = KidsPlaybackFrame()
    let subject = PassthroughSubject<KidsPlaybackDriverEvent, Never>()
    var events: AnyPublisher<KidsPlaybackDriverEvent, Never> {
        subject.eraseToAnyPublisher()
    }

    var starts = 0
    var reports = 0
    var pauses = 0
    var stops = 0
    var seeks: [Double] = []
    func start() {
        starts += 1
        subject.send(.updated)
    }

    func beginReporting() {
        reports += 1
    }

    func togglePlayPause() {}
    func pause() {
        pauses += 1
    }

    func seek(seconds: Double) {
        seeks.append(seconds)
    }

    func stop() async {
        stops += 1
    }

    func advance(_ seconds: Double, output: Int = 1) {
        frame.seconds = seconds
        frame.playing = true
        frame.displayedPictures = output
        subject.send(.updated)
    }
}

@MainActor
private final class Delegate: KidsPlaybackSessionDelegate {
    let isPreview = false
    var began = 0
    var checkpoints: [Double] = []
    var completions = 0
    var continuations = 0
    var stopRequests = 0
    var retries: [Double] = []
    var failures: [KidsPlaybackFailure] = []
    func playbackBegan(_ session: KidsPlaybackController) {
        began += 1
    }

    func playbackCheckpoint(_ session: KidsPlaybackController, seconds: Double) {
        checkpoints.append(seconds)
    }

    func completed(_ session: KidsPlaybackController) async {
        completions += 1
    }

    func continuePlayback(_ session: KidsPlaybackController) async {
        continuations += 1
    }

    func stopPlaybackFromSession() async {
        stopRequests += 1
    }

    func retryPlayback(_ session: KidsPlaybackController, position: Double) {
        retries.append(position)
    }

    func playbackFailed(_ session: KidsPlaybackController, error: KidsPlaybackFailure) {
        failures.append(error)
    }
}

@MainActor
private final class Fixture {
    let driver = Driver()
    let delegate = Delegate()
    var date = Date(timeIntervalSince1970: 1000)
    lazy var session = KidsPlaybackController(
        item: item,
        title: item,
        mode: .movie,
        position: 120,
        episodes: [],
        driver: driver,
        delegate: delegate,
        now: { [unowned self] in self.date }
    )
    let item = KidsItem(id: "approved-movie", name: "Movie", kind: .movie, libraryID: "kids-movies", runtime: 300)
}

@Test @MainActor
func `reports begin only after decoded output beyond durable resume`() async {
    let f = Fixture()
    f.session.start()
    f.driver.advance(120.5, output: 0)
    #expect(f.delegate.began == 0)
    f.driver.advance(120.5)
    f.driver.advance(121)
    #expect(f.delegate.began == 1)
    #expect(f.driver.reports == 1)
    await f.session.stop()
}

@Test @MainActor
func `failed open retry retains durable requested position`() async {
    let f = Fixture()
    f.session.start()
    f.driver.frame.terminal = true
    f.driver.frame.seconds = 0
    f.driver.frame.failed = true
    f.driver.subject.send(.updated)
    #expect(f.session.failed && f.session.recovery)
    await f.session.retry()
    #expect(f.delegate.retries == [120])
    #expect(f.delegate.checkpoints.last == 120)
    #expect(f.driver.stops == 1)
}

@Test @MainActor
func `seek requires pause and clamps runtime without accepting nonfinite input`() async {
    let f = Fixture()
    f.session.start()
    f.driver.advance(121)
    f.driver.frame.seekable = true
    f.session.seek(15)
    #expect(f.driver.seeks.isEmpty)
    f.driver.frame.paused = true
    f.driver.subject.send(.updated)
    f.session.seek(.infinity)
    f.session.seek(1000)
    f.session.seek(-1000)
    #expect(f.driver.seeks == [300, 0])
    await f.session.stop()
}

@Test @MainActor
func `terminal clock does not overwrite checkpoint and stop is idempotent`() async {
    let f = Fixture()
    f.session.start()
    f.driver.advance(200)
    f.driver.frame.terminal = true
    f.driver.frame.seconds = 0
    f.driver.subject.send(.updated)
    #expect(f.session.seconds == 200)
    await f.session.stop()
    await f.session.stop()
    #expect(f.driver.stops == 1)
    #expect(f.delegate.checkpoints.last == 200)
    f.driver.subject.send(.failure(.authentication))
    #expect(f.delegate.failures.isEmpty)
}

@Test @MainActor
func `natural end requires began and is delivered only once`() async {
    let f = Fixture()
    f.session.start()
    f.driver.subject.send(.naturalEnd)
    await Task.yield()
    #expect(f.delegate.completions == 0)
    f.driver.advance(121)
    f.driver.subject.send(.naturalEnd)
    f.driver.subject.send(.naturalEnd)
    for _ in 0 ..< 10 {
        await Task.yield()
    }
    #expect(f.delegate.completions == 1)
    await f.session.stop()
}

@Test @MainActor
func `stalled buffering recovers after fifteen seconds`() async {
    let f = Fixture()
    f.session.start()
    await f.session.tick()
    f.date += 14
    await f.session.tick()
    #expect(!f.session.recovery)
    f.date += 1
    await f.session.tick()
    #expect(f.session.recovery)
    #expect(f.driver.pauses == 1)
    await f.session.stop()
}

@Test @MainActor
func `countdown survives native stop and requests one next item`() async {
    let f = Fixture()
    f.session.start()
    f.driver.advance(121)
    f.session.showCountdown = true
    f.session.countdown = 10
    await f.session.stop()
    for _ in 0 ..< 10 {
        await f.session.tick()
    }
    #expect(f.delegate.continuations == 1)
    #expect(f.driver.stops == 1)
}

@Test @MainActor
func `failure classification and background checkpoint reach application port`() async {
    let f = Fixture()
    f.session.start()
    f.driver.advance(190)
    f.driver.subject.send(.failure(.authentication))
    f.session.pauseOnBackground()
    #expect(f.delegate.failures == [.authentication])
    #expect(f.delegate.checkpoints.last == 190)
    #expect(f.driver.pauses == 1)
    await f.session.stop()
}

@Test @MainActor
func `back hides controls before requesting application stop`() async {
    let f = Fixture()
    f.session.start()
    f.driver.advance(121)
    f.session.reveal()
    await f.session.handleBack()
    #expect(!f.session.controlsVisible)
    #expect(f.delegate.stopRequests == 0)
    await f.session.handleBack()
    #expect(f.delegate.stopRequests == 1)
    await f.session.stop()
}
