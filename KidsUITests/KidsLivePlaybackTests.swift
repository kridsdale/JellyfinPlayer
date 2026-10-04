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

    private func launchRealAccount(arguments: [String] = []) {
        app.launchArguments = arguments
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
        capture("real-title-before-playback")
        focusedSelect(app.buttons[action])
        XCTAssertTrue(
            app.buttons["kids.player.surface"].waitForExistence(timeout: 20),
            "The real stream must leave buffering and expose the player surface."
        )
        capture("real-stream-controls-hidden")
    }

    private func pauseAndReadPosition() -> Int {
        XCUIRemote.shared.press(.playPause)
        let play = app.buttons["kids.player.playpause"]
        let paused = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == true AND label == %@", "Play"), object: play)
        let result = XCTWaiter.wait(for: [paused], timeout: 5)
        capture("real-stream-after-remote-pause")
        XCTAssertEqual(result, .completed, "Actual transport control: \(play.exists ? play.label : "missing")")
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
        let pause = app.buttons["kids.player.playpause"]
        let resumed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == true AND label == %@", "Pause"), object: pause)
        let result = XCTWaiter.wait(for: [resumed], timeout: 5)
        capture("real-stream-after-remote-resume")
        XCTAssertEqual(result, .completed, "Actual resumed control: \(pause.exists ? pause.label : "missing")")
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

    private func naturalIDs() throws -> (String, String) {
        let environment = ProcessInfo.processInfo.environment
        guard environment["KIDS_RUN_NATURAL"] == "1" else {
            throw XCTSkip("Natural-end tests require a documented near-end local resume checkpoint.")
        }
        return try (XCTUnwrap(environment["KIDS_NATURAL_FIRST_ID"]), XCTUnwrap(environment["KIDS_NATURAL_NEXT_ID"]))
    }

    private func revealAndVerifyTitle(_ itemID: String) {
        focusedSelect(app.buttons["kids.player.surface"])
        XCTAssertTrue(app.staticTexts["kids.player.title.\(itemID)"].waitForExistence(timeout: 5))
    }

    func testRealNaturalEpisodeTransition() throws {
        let (first, next) = try naturalIDs()
        launchRealAccount()
        openFirstTitle(action: "kids.action.next")
        revealAndVerifyTitle(first)
        let stop = app.buttons["kids.player.countdown.stop"]
        XCTAssertTrue(stop.waitForExistence(timeout: 60), "Actual VLC EOF must start the next-episode countdown.")
        XCTAssertTrue(stop.hasFocus)
        capture("real-natural-end-countdown")
        XCTAssertTrue(app.buttons["kids.player.surface"].waitForExistence(timeout: 30), "Countdown must start a new real stream.")
        revealAndVerifyTitle(next)
        allowPlaybackToProgress()
        let position = pauseAndReadPosition()
        XCTAssertGreaterThan(position, 1)
        capture("real-natural-next-episode")
    }

    func testRealSessionCapAtNaturalEnd() throws {
        let (_, next) = try naturalIDs()
        launchRealAccount()
        openFirstTitle(action: "kids.action.next")
        revealAndVerifyTitle(next)
        let back = app.buttons["Back to shows"]
        XCTAssertTrue(back.waitForExistence(timeout: 60), "The second actual EOF must stop at the persisted two-episode limit.")
        XCTAssertFalse(app.buttons["kids.player.countdown.stop"].exists)
        XCTAssertFalse(app.buttons["kids.player.surface"].exists)
        capture("real-natural-two-episode-limit")
        allowPlaybackToProgress()
        XCTAssertTrue(back.exists, "Session ending must not autoplay after the cap.")
        focusedSelect(back)
        XCTAssertTrue(firstCard.waitForExistence(timeout: 15))
    }

    func testRealRecoveryClearsCatalogAndPreservesSavedAccount() {
        launchRealAccount()
        let showID = firstCard.identifier
        for (fault, message) in [
            ("invalid-token", "A grown-up needs to sign in again."),
            ("changed-libraries", "Use an account with access only to Kid TV and Kid Movies, without administration or deletion."),
            ("unavailable", "Your shows are taking a break.")
        ] {
            app.terminate()
            app.launchArguments = ["--kids-validation=\(fault)"]
            app.launch()
            XCTAssertTrue(app.staticTexts[message].waitForExistence(timeout: 25))
            XCTAssertEqual(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "kids.card.")).count, 0)
            XCTAssertFalse(app.buttons["kids.category.shows"].exists)
            XCTAssertFalse(app.buttons["kids.player.surface"].exists)
            capture("real-http-\(fault)-neutral-screen")
            app.terminate()
            launchRealAccount()
            XCTAssertEqual(firstCard.identifier, showID, "The untouched saved account must recover its approved catalog.")
        }
    }

    func testRealStreamFailureRetriesExactItem() throws {
        guard let expected = ProcessInfo.processInfo.environment["KIDS_RECOVERY_ITEM_ID"] else {
            throw XCTSkip("Exact-item stream recovery requires the current local cursor ID, without changing that cursor.")
        }
        let minimum = Int(ProcessInfo.processInfo.environment["KIDS_RECOVERY_MIN_SECONDS"] ?? "0") ?? 0
        launchRealAccount(arguments: ["--kids-validation=stream-unavailable"])
        focusedSelect(firstCard)
        let next = app.buttons["kids.action.next"]
        XCTAssertTrue(next.waitForExistence(timeout: 20))
        focusedSelect(next)
        // Repeated Select during the disabled pending start must not produce another owner.
        if next.exists && !next.isEnabled {
            XCUIRemote.shared.press(.select)
        }
        let retry = app.buttons["Try again"]
        let recovered = retry.waitForExistence(timeout: 35)
        capture("real-vlc-refused-connection")
        XCTAssertTrue(recovered, "A real refused VLC connection must expose recovery within the bounded prepare/open wait.")
        XCTAssertFalse(app.buttons["kids.player.surface"].exists)
        allowPlaybackToProgress()
        XCTAssertTrue(retry.exists, "Failed starts must wait for deliberate retry.")
        focusedSelect(retry)
        XCTAssertTrue(app.buttons["kids.player.surface"].waitForExistence(timeout: 25))
        revealAndVerifyTitle(expected)
        allowPlaybackToProgress()
        let resumed = pauseAndReadPosition()
        XCTAssertGreaterThanOrEqual(resumed, minimum - 2, "Retry must preserve the exact failed item's local checkpoint.")
        XCTAssertGreaterThan(resumed, 1)
        capture("real-vlc-exact-item-recovered")
    }

    func testRealShufflePlaysEpisode() {
        launchRealAccount()
        focusedSelect(firstCard)
        let shuffle = app.buttons["kids.action.shuffle"]
        XCTAssertTrue(shuffle.waitForExistence(timeout: 20))
        capture("real-shuffle-title")
        XCUIRemote.shared.press(.right)
        focusedSelect(shuffle)
        XCTAssertTrue(app.buttons["kids.player.surface"].waitForExistence(timeout: 25))
        let elapsed = provePauseSeekAndProgress("real-shuffle-paused-frame")
        XCTAssertGreaterThan(elapsed, 15)
        let title = app.staticTexts.matching(NSPredicate(format: "identifier BEGINSWITH %@", "kids.player.title.")).firstMatch
        XCTAssertTrue(title.exists)
        XCTAssertEqual(String(title.identifier.dropFirst("kids.player.title.".count)).count, 32)
        let episodeID = title.identifier
        capture("real-shuffle-playing-frame")
        app.terminate()
        launchRealAccount()
        XCTAssertFalse(app.buttons["kids.player.surface"].exists, "Relaunch must never autoplay.")
        focusedSelect(firstCard)
        XCTAssertTrue(app.buttons["kids.action.shuffle"].waitForExistence(timeout: 20))
        XCUIRemote.shared.press(.right)
        focusedSelect(app.buttons["kids.action.shuffle"])
        XCTAssertTrue(app.buttons["kids.player.surface"].waitForExistence(timeout: 25))
        allowPlaybackToProgress()
        let restored = pauseAndReadPosition()
        XCTAssertGreaterThanOrEqual(restored, elapsed - 2, "An interrupted Shuffle must restore its paused checkpoint.")
        XCTAssertTrue(app.staticTexts[episodeID].exists, "An interrupted Shuffle must resume the same episode.")
        capture("real-shuffle-restored-position")
    }
}
