//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Combine
import Foundation
@testable import SwiftfinVLC
import SwiftUI
import XCTest

@MainActor
final class VLCPlaybackOwnershipTests: XCTestCase {
    private final class Engine: VLCNativeEngine {
        var frame = VLCPlaybackFrame()
        var subtitleTracks: [VLCSubtitleTrack] = []
        var seeks: [Duration] = []
        var opens = 0
        var stops = 0
        var shutdowns = 0
        var rejectSeek = false
        var update: (@MainActor () -> Void)?
        func surface(controller: VLCPlaybackController, generation: UUID) -> AnyView {
            AnyView(Color.clear)
        }

        func observeUpdates(_ update: @escaping @MainActor () -> Void) {
            self.update = update
        }

        func cancelUpdates() {
            update = nil
        }

        func open(_ request: VLCPlaybackRequest) throws {
            opens += 1
        }

        func play() throws {}
        func pause() {}
        func stop() {
            stops += 1
        }

        func seek(_ time: Duration) throws {
            if rejectSeek {
                throw NSError(domain: "fixture", code: 1)
            }
            seeks.append(time)
        }

        func jump(_ offset: Duration) {}
        func rate(_ value: Float) throws {}
        func audioTrack(_ index: Int?) {}
        func subtitleTrack(_ index: Int?) {}
        func aspectFill(_ value: Bool) {}
        func audioDelay(_ value: Duration) throws {}
        func subtitleDelay(_ value: Duration) throws {}
        func subtitleStyle(_ value: VLCSubtitleStyle) {}
        func shutdown() async -> Bool {
            shutdowns += 1
            return true
        }
    }

    private func request(start: Duration = .seconds(120), live: Bool = false) -> VLCPlaybackRequest {
        .init(
            url: URL(string: "https://localhost.invalid/video?api_key=private-fixture")!,
            start: start,
            runtime: .seconds(900),
            live: live,
            subtitleURLs: [],
            subtitleStyle: .init(fontName: "fixture", colorRGB: nil, approximatePoints: 16)
        )
    }

    func testAbsoluteResumeWaitsForSeekableTimelineAndAppliesOnce() {
        let engine = Engine()
        let player = VLCPlaybackController(engine: engine), generation = UUID()
        var events: [VLCPlaybackEvent] = []
        player.onEvent = { events.append($0) }
        player.open(request(), generation: generation)
        engine.frame.state = .playing
        player.observed(.state, generation: generation)
        XCTAssertTrue(player.frame.applyingStartPosition)
        XCTAssertEqual(engine.seeks, [])
        engine.frame.seekable = true
        player.observed(.seekable, generation: generation)
        player.observed(.state, generation: generation)
        XCTAssertEqual(engine.seeks, [.seconds(120)])
        XCTAssertFalse(player.frame.applyingStartPosition)
        XCTAssertEqual(events.filter { $0 == .resumePosition(.seconds(120)) }.count, 1)
    }

    func testUserSeekSupersedesPendingResumeAndFailedSeekIsClassified() {
        let engine = Engine()
        let controller = VLCPlaybackController(engine: engine), generation = UUID()
        var events: [VLCPlaybackEvent] = []
        controller.onEvent = { events.append($0) }
        controller.open(request(), generation: generation)
        engine.frame.seekable = true
        controller.seek(.seconds(300))
        controller.observed(.seekable, generation: generation)
        XCTAssertEqual(engine.seeks, [.seconds(300)])
        engine.rejectSeek = true
        controller.seek(.seconds(301))
        XCTAssertEqual(events.last, .operationRejected(.seek))
    }

    func testOldSurfaceCallbacksCannotMutateReplacementOrStoppedSession() {
        let engine = Engine(), player = VLCPlaybackController(engine: engine)
        let old = UUID(), current = UUID()
        var events: [VLCPlaybackEvent] = []
        player.onEvent = { events.append($0) }
        player.open(request(), generation: old)
        player.open(request(start: .seconds(200)), generation: current)
        engine.frame.state = .playing
        engine.frame.seekable = true
        player.observed(.state, generation: old)
        XCTAssertEqual(engine.seeks, [])
        XCTAssertTrue(events.isEmpty)
        player.observed(.state, generation: current)
        XCTAssertEqual(engine.seeks, [.seconds(200)])
        events.removeAll()
        player.stop()
        player.observed(.state, generation: current)
        XCTAssertTrue(events.isEmpty)
        XCTAssertFalse(player.frame.applyingStartPosition)
    }

    func testNaturalEndReportsTimelineOnceAndLiveStreamCannotAdvance() {
        let engine = Engine(), player = VLCPlaybackController(engine: engine), generation = UUID()
        var events: [VLCPlaybackEvent] = []
        player.onEvent = { events.append($0) }
        player.open(request(start: .zero), generation: generation)
        engine.frame.reachedEnd = true
        player.observed(.end, generation: generation)
        player.observed(.end, generation: generation)
        XCTAssertEqual(events, [.naturalEnd(.seconds(900))])
        events.removeAll()
        let live = UUID()
        player.open(request(live: true), generation: live)
        player.observed(.end, generation: live)
        XCTAssertTrue(events.isEmpty)
        XCTAssertFalse(player.frame.applyingStartPosition)
    }

    func testBufferingCannotOverridePausedTransportAndMetricsStayNumeric() {
        let engine = Engine(), player = VLCPlaybackController(engine: engine), generation = UUID()
        player.open(request(start: .zero), generation: generation)
        engine.frame.state = .playing
        engine.frame.bufferFill = 0.5
        engine.frame.displayedPictures = 2
        engine.frame.videoSize = CGSize(width: 720, height: 400)
        player.observed(.buffer, generation: generation)
        XCTAssertTrue(player.frame.buffering)
        engine.frame.state = .paused
        player.observed(.state, generation: generation)
        player.observed(.buffer, generation: generation)
        XCTAssertFalse(player.frame.buffering)
        XCTAssertEqual(player.frame.displayedPictures, 2)
        XCTAssertEqual(player.frame.videoSize.width, 720)
        XCTAssertFalse(String(describing: request()).contains("private-fixture"))
        XCTAssertFalse(String(reflecting: request()).contains("api_key"))
    }

    func testShutdownCancelsNativeUpdatesBeforeReleasingOutput() async {
        let engine = Engine(), player = VLCPlaybackController(engine: engine), generation = UUID()
        var updates = 0
        let subscription = player.updates.sink { updates += 1 }
        player.open(request(), generation: generation)
        engine.update?()
        XCTAssertEqual(updates, 1)
        player.stop()
        engine.update?()
        XCTAssertEqual(updates, 1)
        let released = await player.shutdown()
        XCTAssertTrue(released)
        XCTAssertEqual(engine.shutdowns, 1)
        XCTAssertNil(engine.update)
        withExtendedLifetime(subscription) {}
    }
}
