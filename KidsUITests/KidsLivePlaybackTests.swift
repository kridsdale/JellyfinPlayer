//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import XCTest

/// Opt-in tests of an already configured real restricted account. Never substitutes a fixture or logs credentials.
@MainActor
final class KidsLivePlaybackTests: XCTestCase {
    private let app = XCUIApplication(bundleIdentifier: "com.kridsdale.JellyfinPlayer")

    private var didLaunch = false

    override func setUpWithError() throws {
        continueAfterFailure = false
        let optIn = ProcessInfo.processInfo.environment["KIDS_RUN_LIVE"]
        guard optIn == "1" else {
            let status = optIn == nil ? "missing" : "disabled"
            throw XCTSkip("Live playback opt-in is \(status). Configure the real kids account before enabling KIDS_RUN_LIVE=1.")
        }
    }

    override func tearDown() {
        if didLaunch {
            app.terminate()
        }
        super.tearDown()
    }

    private func launchRealAccount() {
        app.launchArguments = []
        app.launchEnvironment["DYLD_FRAMEWORK_PATH"] = ""
        app.launchEnvironment["DYLD_LIBRARY_PATH"] = ""
        app.launch()
        didLaunch = true
        XCTAssertTrue(
            app.buttons["kids.category.shows"].waitForExistence(timeout: 30),
            "Configure the real restricted account first. Live tests never fall back to preview data."
        )
        XCTAssertTrue(app.buttons["kids.category.movies"].exists)
    }

    private var firstCard: XCUIElement {
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "kids.card.")).firstMatch
    }

    private func focusedSelect(_ element: XCUIElement) {
        let focused = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hasFocus == true"), object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [focused], timeout: 5), .completed)
        XCUIRemote.shared.press(.select)
    }

    private func openFirstTitle(action: String) {
        XCTAssertTrue(firstCard.waitForExistence(timeout: 10))
        focusedSelect(firstCard)
        XCTAssertTrue(app.buttons[action].waitForExistence(timeout: 20))
        focusedSelect(app.buttons[action])
        XCTAssertTrue(
            app.buttons["kids.player.surface"].waitForExistence(timeout: 20),
            "The real stream must leave buffering and expose the player surface."
        )
    }

    private func pauseAndReadPosition() -> Int {
        XCUIRemote.shared.press(.playPause)
        let play = app.buttons["kids.player.playpause"]
        let paused = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == true AND label == %@", "Play"), object: play)
        XCTAssertEqual(XCTWaiter.wait(for: [paused], timeout: 5), .completed)
        let timeline = app.descendants(matching: .any)["kids.player.timeline"]
        XCTAssertTrue(timeline.waitForExistence(timeout: 5))
        return position(timeline)
    }

    private func position(_ timeline: XCUIElement) -> Int {
        let parts = (timeline.value as? String ?? "").split(separator: ":").compactMap { Int($0) }
        XCTAssertEqual(parts.count, 2, "The actual paused timeline must report minutes and seconds.")
        guard parts.count == 2 else { return -1 }
        return parts[0] * 60 + parts[1]
    }

    private func allowPlaybackToProgress() {
        let interval = expectation(description: "Observe real playback over four seconds")
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { interval.fulfill() }
        wait(for: [interval], timeout: 6)
    }

    private func provePauseSeekAndProgress(_ name: String) -> Int {
        allowPlaybackToProgress()
        let before = pauseAndReadPosition()
        let timeline = app.descendants(matching: .any)["kids.player.timeline"]
        XCUIRemote.shared.press(.up)
        XCTAssertTrue(timeline.hasFocus)
        XCUIRemote.shared.press(.right)
        let seeked = position(timeline)
        XCTAssertEqual(Double(seeked), Double(before + 15), accuracy: 1)
        XCUIRemote.shared.press(.playPause)
        allowPlaybackToProgress()
        let after = pauseAndReadPosition()
        XCTAssertGreaterThan(after, seeked + 1, "Resume must advance actual stream time.")
        capture(name)
        return after
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testRealEpisodePauseSeekAndResumeAfterRelaunch() {
        launchRealAccount()
        let showID = firstCard.identifier
        openFirstTitle(action: "kids.action.next")
        let saved = provePauseSeekAndProgress("real-episode-paused-frame")
        // Termination backgrounds the real app; its production checkpoint must survive this process.
        app.terminate()
        launchRealAccount()
        XCTAssertFalse(app.buttons["kids.player.surface"].exists, "Relaunch must never autoplay.")
        XCTAssertEqual(firstCard.identifier, showID)
        openFirstTitle(action: "kids.action.next")
        allowPlaybackToProgress()
        let resumed = pauseAndReadPosition()
        XCTAssertGreaterThanOrEqual(resumed, saved - 2, "Next must restore the real ordered checkpoint.")
        capture("real-episode-restored-position")
    }

    func testRealMoviePauseSeekAndResume() {
        launchRealAccount()
        let initialCardID = firstCard.identifier
        XCUIRemote.shared.press(.up)
        XCUIRemote.shared.press(.right)
        focusedSelect(app.buttons["kids.category.movies"])
        let changed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            self.firstCard.exists && self.firstCard.identifier != initialCardID
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [changed], timeout: 10), .completed)
        XCUIRemote.shared.press(.down)
        openFirstTitle(action: "kids.action.play")
        _ = provePauseSeekAndProgress("real-movie-paused-frame")
        XCTAssertFalse(app.buttons["kids.action.shuffle"].exists)
        XCUIRemote.shared.press(.menu)
        XCUIRemote.shared.press(.menu)
        let play = app.buttons["kids.action.play"]
        XCTAssertTrue(play.waitForExistence(timeout: 10))
        XCTAssertTrue(play.label.contains("Resume"))
    }
}
