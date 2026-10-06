//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import AVFoundation
import Foundation
@testable import SwiftfinNativePlayback
import SwiftUI
import XCTest

@MainActor
final class NativePlaybackOwnershipTests: XCTestCase {
    private final class Engine: NativePlaybackEngine {
        var time: Duration = .zero
        var callbacks: [@MainActor (NativeObservation) -> Void] = []
        var completions: [@MainActor (Bool) -> Void] = []
        var requests: [NativePlaybackRequest] = []
        var seeks: [Duration] = []
        var plays = 0
        var pauses = 0
        var stops = 0
        var rates: [Float] = []
        var fills: [Bool] = []
        func open(
            _ request: NativePlaybackRequest,
            generation: UUID,
            receive: @escaping @MainActor (NativeObservation, UUID) -> Void
        ) {
            requests.append(request)
            callbacks.append { receive($0, generation) }
        }

        func seek(_ time: Duration, completion: @escaping @MainActor (Bool) -> Void) {
            seeks.append(time)
            completions.append(completion)
        }

        func play() {
            plays += 1
        }

        func pause() {
            pauses += 1
        }

        func stop() {
            stops += 1
        }

        func rate(_ value: Float) {
            rates.append(value)
        }

        func aspectFill(_ value: Bool) {
            fills.append(value)
        }

        func surface(showControls _: Bool) -> AnyView {
            AnyView(Color.clear)
        }
    }

    private func request(start: Duration = .seconds(120), live: Bool = false) -> NativePlaybackRequest {
        .init(
            url: URL(string: "https://localhost.invalid/video?api_key=synthetic-secret")!,
            start: start,
            live: live,
            title: "Synthetic show",
            subtitle: "Synthetic episode",
            overview: "Synthetic overview"
        )
    }

    func testReadyAppliesAbsoluteResumeOnceAndClockWaitsForCompletedSeek() {
        let engine = Engine(), player = NativePlaybackController(engine: engine)
        var events: [NativePlaybackEvent] = []
        player.onEvent = { events.append($0) }
        player.open(request())
        engine.callbacks[0](.clock(.seconds(1)))
        engine.callbacks[0](.state(.paused))
        XCTAssertTrue(events.isEmpty)
        XCTAssertTrue(engine.seeks.isEmpty)
        engine.callbacks[0](.ready)
        engine.callbacks[0](.ready)
        engine.callbacks[0](.clock(.seconds(2)))
        XCTAssertEqual(engine.seeks, [.seconds(120)])
        XCTAssertEqual(engine.plays, 0)
        XCTAssertTrue(events.isEmpty)
        engine.completions[0](true)
        XCTAssertEqual(engine.plays, 1)
        engine.completions[0](true)
        XCTAssertEqual(engine.plays, 1)
        XCTAssertEqual(events, [.resumePosition(.seconds(120))])
        engine.callbacks[0](.clock(.seconds(121)))
        XCTAssertEqual(events.last, .clock(.seconds(121)))
    }

    func testPauseDuringPreparationOrResumeCompletionCannotAutoplay() {
        let engine = Engine(), player = NativePlaybackController(engine: engine)
        player.open(request())
        player.pause()
        engine.callbacks[0](.ready)
        engine.completions[0](true)
        XCTAssertEqual(engine.plays, 0)
        player.play()
        XCTAssertEqual(engine.plays, 1)
        engine.callbacks[0](.state(.paused))
        player.seek(.seconds(250))
        player.pause()
        engine.completions[1](true)
        XCTAssertEqual(engine.plays, 1)
    }

    func testOldItemStatusClockEndAndSeekCompletionCannotMutateReplacementOrStop() {
        let engine = Engine(), player = NativePlaybackController(engine: engine)
        var events: [NativePlaybackEvent] = []
        player.onEvent = { events.append($0) }
        player.open(request())
        engine.callbacks[0](.ready)
        player.open(request(start: .seconds(200)))
        engine.callbacks[0](.failed)
        engine.callbacks[0](.state(.playing))
        engine.callbacks[0](.clock(.seconds(700)))
        engine.callbacks[0](.ended)
        engine.completions[0](true)
        XCTAssertTrue(events.isEmpty)
        XCTAssertEqual(engine.plays, 0)
        engine.callbacks[1](.ready)
        XCTAssertEqual(engine.seeks, [.seconds(120), .seconds(200)])
        player.stop()
        engine.completions[1](true)
        engine.callbacks[1](.state(.playing))
        XCTAssertTrue(events.isEmpty)
        XCTAssertEqual(engine.plays, 0)
    }

    func testNewSeekSupersedesCompletionAndHostStopDuringResumeCannotRestart() {
        let engine = Engine(), player = NativePlaybackController(engine: engine)
        var events: [NativePlaybackEvent] = []
        player.onEvent = { events.append($0) }
        player.open(request())
        engine.callbacks[0](.ready)
        engine.completions[0](true)
        player.seek(.seconds(300))
        player.seek(.seconds(400))
        engine.completions[1](true)
        XCTAssertEqual(events.count, 1)
        player.onEvent = { events.append($0)
            player.stop()
        }
        engine.completions[2](true)
        XCTAssertEqual(events.last, .resumePosition(.seconds(400)))
        XCTAssertEqual(engine.plays, 1)
        player.onEvent = nil
    }

    func testFailureStopsAndFailedInitialSeekDoesNotPlay() {
        let engine = Engine(), player = NativePlaybackController(engine: engine)
        var events: [NativePlaybackEvent] = []
        player.onEvent = { events.append($0) }
        player.open(request())
        engine.callbacks[0](.ready)
        engine.completions[0](false)
        XCTAssertEqual(events, [.playbackFailed])
        XCTAssertEqual(engine.plays, 0)
        engine.callbacks[0](.ready)
        XCTAssertEqual(engine.seeks.count, 1)
        player.open(request())
        engine.callbacks[1](.failed)
        engine.callbacks[1](.failed)
        XCTAssertEqual(events, [.playbackFailed, .playbackFailed])
    }

    func testNaturalEndIsOnceAndLiveDoesNotResumeOrAdvance() {
        let engine = Engine(), player = NativePlaybackController(engine: engine)
        var events: [NativePlaybackEvent] = []
        player.onEvent = { events.append($0) }
        player.open(request())
        engine.callbacks[0](.ended)
        XCTAssertTrue(events.isEmpty)
        engine.callbacks[0](.ready)
        engine.completions[0](true)
        engine.callbacks[0](.ended)
        engine.callbacks[0](.ended)
        XCTAssertEqual(events.filter { $0 == .naturalEnd }.count, 1)
        events.removeAll()
        player.open(request(live: true))
        engine.callbacks[1](.ready)
        XCTAssertEqual(engine.seeks.last, .zero)
        engine.completions[1](true)
        engine.callbacks[1](.ended)
        XCTAssertFalse(events.contains(.naturalEnd))
    }

    func testCommandsAfterStopAndInvalidRatesAreRejectedAndOwnerReleasesEngine() {
        let engine = Engine()
        var player: NativePlaybackController? = NativePlaybackController(engine: engine)
        weak let weakPlayer = player
        player?.setRate(2)
        XCTAssertTrue(engine.rates.isEmpty)
        player?.open(request())
        player?.setRate(.nan)
        player?.setRate(.infinity)
        player?.setRate(-1)
        player?.setRate(0)
        player?.setRate(1.5)
        player?.setAspectFill(true)
        XCTAssertEqual(engine.rates, [1.5])
        XCTAssertEqual(engine.fills, [true])
        player?.stop()
        player?.play()
        player?.pause()
        player?.seek(.seconds(200))
        XCTAssertEqual(engine.plays, 0)
        let stops = engine.stops
        player = nil
        XCTAssertNil(weakPlayer)
        XCTAssertEqual(engine.stops, stops + 1)
    }

    func testWorkerExecutorCallbacksTransferOnlyValuesToOwner() async {
        let engine = Engine(), player = NativePlaybackController(engine: engine)
        var events: [NativePlaybackEvent] = []
        player.onEvent = { events.append($0) }
        player.open(request())
        let status = engine.callbacks[0]
        await Task.detached { await status(.ready) }.value
        XCTAssertEqual(engine.seeks, [.seconds(120)])
        let completion = engine.completions[0]
        await Task.detached { await completion(true) }.value
        await Task.detached { await status(.clock(.seconds(121))) }.value
        XCTAssertEqual(events.last, .clock(.seconds(121)))
        XCTAssertEqual(engine.plays, 1)
    }

    func testJumpUsesNativeTimelineAndClampsBeforeZero() {
        let engine = Engine(), player = NativePlaybackController(engine: engine)
        player.open(request())
        engine.callbacks[0](.ready)
        engine.completions[0](true)
        engine.time = .seconds(100)
        player.jump(.seconds(15))
        XCTAssertEqual(engine.seeks.last, .seconds(115))
        player.jump(.seconds(-200))
        XCTAssertEqual(engine.seeks.last, .zero)
    }

    func testMetadataIsBuiltInsideNativeOwnerAndRequestDescriptionsAreRedacted() async throws {
        let r = request()
        XCTAssertFalse(String(describing: r).contains("Synthetic"))
        XCTAssertFalse(String(reflecting: r).contains("api_key"))
        let values = AVPlaybackEngine.metadata(r)
        XCTAssertEqual(values.count, 3)
        let title = try await values.first { $0.identifier == .commonIdentifierTitle }?.load(.stringValue)
        let subtitle = try await values.first { $0.identifier == .iTunesMetadataTrackSubTitle }?.load(.stringValue)
        let overview = try await values.first { $0.identifier == .commonIdentifierDescription }?.load(.stringValue)
        XCTAssertEqual(title, r.title)
        XCTAssertEqual(subtitle, r.subtitle)
        XCTAssertEqual(overview, r.overview)
        XCTAssertTrue(values.allSatisfy { $0.extendedLanguageTag == "und" })
        let noSubtitle = NativePlaybackRequest(url: r.url, start: .seconds(-10), title: "Synthetic")
        XCTAssertEqual(noSubtitle.start, .zero)
        XCTAssertEqual(AVPlaybackEngine.metadata(noSubtitle).count, 3)
    }
}
