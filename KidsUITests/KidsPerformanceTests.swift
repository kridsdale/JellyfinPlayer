//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

// SPDX-License-Identifier: MPL-2.0
import XCTest

/// Profiling uses the real saved restricted account in a Release build. No fixtures,
/// credentials, artificial EOF, server changes or media/cache mutations.
@MainActor
final class KidsPerformanceTests: XCTestCase {
    private let app = XCUIApplication()
    private var registeredCleanup = false
    override func setUpWithError() throws {
        continueAfterFailure = false
        guard ProcessInfo.processInfo.environment["KIDS_RUN_PROFILE"] == "1" else {
            throw XCTSkip("Opt in with KIDS_RUN_PROFILE=1 after configuring the real restricted simulator account.")
        }
    }

    private var firstCard: XCUIElement {
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "kids.card.")).firstMatch
    }

    private func wait(_ seconds: Double) {
        let done = expectation(description: "Allow actual UI/network/playback observations")
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { done.fulfill() }
        wait(for: [done], timeout: seconds + 3)
    }

    private func select(_ element: XCUIElement) {
        let focused = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hasFocus == true"), object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [focused], timeout: 8), .completed)
        XCUIRemote.shared.press(.select)
    }

    private func launch() {
        if !registeredCleanup {
            let cleanup = SimulatorApplicationCleanup(app)
            addTeardownBlock { await cleanup.stop() }
            registeredCleanup = true
        }
        app.launchArguments = ["--kids-profile"]
        app.launchEnvironment["DYLD_FRAMEWORK_PATH"] = ""
        app.launchEnvironment["DYLD_LIBRARY_PATH"] = ""
        app.launch()
        XCTAssertEqual(app.label, "KidsJellyFin", "Profile the selected Xcode target rather than a cached app with the same bundle ID.")
        XCTAssertTrue(app.buttons["kids.category.shows"].waitForExistence(timeout: 40))
        XCTAssertTrue(firstCard.waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["kids.player.surface"].exists, "No automatic playback during fresh launch.")
    }

    private func movies() {
        let first = firstCard.identifier
        XCUIRemote.shared.press(.up)
        XCUIRemote.shared.press(.right)
        select(app.buttons["kids.category.movies"])
        let changed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            self.firstCard.exists && self.firstCard.identifier != first
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [changed], timeout: 15), .completed)
        XCUIRemote.shared.press(.down)
    }

    private func capture(_ name: String) {
        let image = XCTAttachment(screenshot: app.screenshot())
        image.name = name
        image.lifetime = .keepAlways
        add(image)
    }

    private func sampleCardIDs() -> [String] {
        // Accessibility query order can change as tvOS promotes the focused card.
        // Freeze visible identities in visual order before sending remote input.
        let cards = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "kids.card."))
            .allElementsBoundByIndex.filter(\.isHittable)
            .sorted { a, b in
                abs(a.frame.midY - b.frame.midY) > 100 ? a.frame.midY < b.frame.midY : a.frame.midX < b.frame.midX
            }
        let ids = Array(cards.prefix(3).map(\.identifier))
        XCTAssertEqual(Set(ids).count, 3)
        return ids
    }

    private func focusCard(_ identifier: String) -> XCUIElement {
        let target = app.buttons[identifier]
        XCTAssertTrue(target.waitForExistence(timeout: 30))
        wait(0.4) // Allow the navigation transition and restored focus to settle.
        for _ in 0 ..< 12 {
            if target.hasFocus {
                return target
            }
            let focused = app.buttons.matching(NSPredicate(format: "hasFocus == true")).firstMatch
            if focused.exists, focused.identifier.hasPrefix("kids.card.") {
                let from = focused.frame, to = target.frame
                if abs(to.midY - from.midY) > 100 {
                    XCUIRemote.shared.press(to.midY < from.midY ? .up : .down)
                } else {
                    XCUIRemote.shared.press(to.midX < from.midX ? .left : .right)
                }
            } else {
                XCUIRemote.shared.press(.down)
            }
            wait(0.15)
        }
        XCTAssertTrue(target.hasFocus, "A stable visible card identity must be reachable with remote input.")
        return target
    }

    private func playAndStop(
        action: String,
        shuffle: Bool = false,
        captureName: String?,
        playingSeconds: Double = 2,
        pausedSeconds: Double = 0
    ) {
        let button = app.buttons[action]
        XCTAssertTrue(button.waitForExistence(timeout: 30))
        if shuffle {
            XCUIRemote.shared.press(.right)
        }
        select(button)
        XCTAssertTrue(app.buttons["kids.player.surface"].waitForExistence(timeout: 30), "A real VLC stream must become visible.")
        wait(playingSeconds)
        XCUIRemote.shared.press(.playPause)
        let play = app.buttons["kids.player.playpause"]
        let paused = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == true AND label == %@", "Play"), object: play)
        XCTAssertEqual(XCTWaiter.wait(for: [paused], timeout: 8), .completed)
        let timeline = app.descendants(matching: .any)["kids.player.timeline"]
        XCTAssertTrue(timeline.waitForExistence(timeout: 5))
        let parts = (timeline.value as? String ?? "").split(separator: ":").compactMap { Int($0) }
        XCTAssertEqual(parts.count, 2)
        if parts.count == 2 {
            XCTAssertGreaterThan(parts[0] * 60 + parts[1], 0)
        }
        if let captureName {
            capture(captureName)
        }
        if pausedSeconds > 0 {
            wait(pausedSeconds)
        }
        XCUIRemote.shared.press(.menu)
        XCUIRemote.shared.press(.menu)
        XCTAssertTrue(app.buttons[action].waitForExistence(timeout: 15))
    }

    /// A finite real stream gives the read-only server observer several playing,
    /// paused and successfully cleared samples; short startup samples cannot do so.
    func testProfileReportingLifecycle() {
        launch()
        select(focusCard(sampleCardIDs()[0]))
        playAndStop(action: "kids.action.next", captureName: "profile-reporting-paused", playingSeconds: 18, pausedSeconds: 6)
        wait(15)
        XCTAssertFalse(app.buttons["kids.player.surface"].exists)
        capture("profile-reporting-stopped")
    }

    func testProfileFreshLaunchAndArtworkRevisits() {
        for run in 0 ..< 4 {
            launch()
            wait(2)
            if run == 0 {
                capture("profile-fresh-shows")
            }
            movies()
            wait(2)
            if run == 0 {
                capture("profile-movies-thumbnails")
            }
            select(firstCard)
            XCTAssertTrue(app.buttons["kids.action.play"].waitForExistence(timeout: 15))
            wait(2)
            XCUIRemote.shared.press(.menu)
            XCTAssertTrue(firstCard.waitForExistence(timeout: 30))
            wait(2)
            if run == 0 {
                capture("profile-revisited-movies")
            }
            app.terminate()
        }
    }

    func testProfileEpisodeAndShuffleStarts() {
        launch()
        // Repeated ordered/resume and fresh Shuffle starts of the verified representative show.
        // The wider discovery trial is retained separately; another show's episode list was rejected.
        let ids = Array(sampleCardIDs().prefix(1))
        for (index, identifier) in ids.enumerated() {
            select(focusCard(identifier))
            for repeatIndex in 0 ..< 2 {
                playAndStop(action: "kids.action.next", captureName: repeatIndex == 0 ? "profile-episode-\(index)" : nil)
            }
            playAndStop(action: "kids.action.shuffle", shuffle: true, captureName: "profile-shuffle-\(index)")
            XCUIRemote.shared.press(.menu)
            XCTAssertTrue(firstCard.waitForExistence(timeout: 30))
        }
    }

    func testProfileMovieStarts() {
        launch()
        movies()
        // Freeze the already focused, verified movie. Query indexes can change with focus,
        // and the wider discovery trial found a separate movie that rendered corrupt video.
        let target = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND hasFocus == true", "kids.card.")).firstMatch
        XCTAssertTrue(target.waitForExistence(timeout: 10))
        select(target)
        for repeatIndex in 0 ..< 4 {
            playAndStop(action: "kids.action.play", captureName: repeatIndex == 0 ? "profile-verified-movie" : nil)
        }
    }
}
