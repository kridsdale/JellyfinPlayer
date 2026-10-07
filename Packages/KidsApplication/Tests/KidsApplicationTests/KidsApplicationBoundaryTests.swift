//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

// SPDX-License-Identifier: MPL-2.0
import Combine
import Foundation
import KidsAccounts
@testable import KidsApplication
import KidsCatalog
import KidsDiagnostics
import KidsDomain
import KidsPlaybackSession
import XCTest

@MainActor
final class KidsApplicationBoundaryTests: XCTestCase {
    private final class Accounts: KidsAccountHost {
        let changes = CurrentValueSubject<KidsAccountIdentity?, Never>(nil)
        var currentIdentity: KidsAccountIdentity? {
            changes.value
        }

        var identityChanges: AnyPublisher<KidsAccountIdentity?, Never> {
            changes.eraseToAnyPublisher()
        }

        struct StorageFailure: Error {}
        var savedPIN: String?
        var pinReadFails = false
        var parentPIN: String? {
            get throws {
                if pinReadFails {
                    throw StorageFailure()
                }
                return savedPIN
            }
        }

        var writes = 0
        var authentications = 0
        var signOuts = 0
        func storeParentPIN(_ pin: String) throws {
            writes += 1
            savedPIN = pin
        }

        func authenticate(
            url: URL,
            serverID: String,
            serverName: String,
            username: String,
            password: String
        ) async throws -> KidsAuthenticatedAccount {
            authentications += 1
            throw KidsContractError.denied
        }

        func signOut() async {
            signOuts += 1
        }
    }

    private final class PlaybackFactory: KidsPlaybackSessionFactory {
        var preparations = 0
        func prepare(
            item: KidsItem,
            title: KidsItem,
            mode: KidsPlaybackMode,
            position: Double,
            episodes: [KidsItem],
            delegate: any KidsPlaybackSessionDelegate,
            performance: KidsPerformanceSpan?,
            simulateStreamFailure: Bool
        ) async throws -> KidsPlaybackController {
            preparations += 1
            throw KidsContractError.denied
        }
    }

    private func identity(
        url: String = "http://localhost:9",
        server: String = "server",
        user: String = "kid",
        token: String = "fixture",
        name: String = "Fixture"
    ) -> KidsAccountIdentity {
        .init(serverURL: URL(string: url)!, serverID: server, serverName: name, userID: user, accessToken: token)
    }

    private func drainIdentityDelivery() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
    }

    func testAccountRevisionTracksFullAuthorizationIdentityOnly() async {
        let accounts = Accounts(), factory = PlaybackFactory()
        let model = KidsAppModel(accounts: accounts, playbackFactory: factory)
        var revision = model.accountRevision
        await drainIdentityDelivery()
        XCTAssertEqual(model.accountRevision, revision)
        for candidate in [
            identity(),
            identity(token: "replacement"),
            identity(url: "http://localhost:8"),
            identity(server: "replacement-server"),
            identity(user: "replacement-kid")
        ] {
            accounts.changes.send(candidate)
            await drainIdentityDelivery()
            XCTAssertNotEqual(model.accountRevision, revision)
            revision = model.accountRevision
            accounts.changes.send(candidate)
            await drainIdentityDelivery()
            XCTAssertEqual(model.accountRevision, revision)
        }
        accounts.changes.send(identity(user: "replacement-kid", name: "Renamed"))
        await drainIdentityDelivery()
        XCTAssertEqual(model.accountRevision, revision)
        XCTAssertEqual(model.serverName, "Renamed")
        accounts.changes.send(nil)
        await drainIdentityDelivery()
        XCTAssertNotEqual(model.accountRevision, revision)
        XCTAssertEqual(factory.preparations, 0)
        XCTAssertEqual(accounts.writes, 0)
        XCTAssertEqual(accounts.authentications, 0)
    }

    func testPreviewRejectsCredentialsBeforeNetworkOrHostMutation() async {
        let accounts = Accounts(), factory = PlaybackFactory()
        let model = KidsAppModel(accounts: accounts, playbackFactory: factory, preview: true)
        XCTAssertTrue(model.unlock("4242"))
        do {
            try await model.signIn(urlText: "http://127.0.0.1:9", username: "fixture", password: "fixture", parentPIN: "1234")
            XCTFail("Synthetic preview activated an account")
        } catch { XCTAssertEqual(error as? KidsContractError, .denied) }
        XCTAssertThrowsError(try model.setPIN("1234"))
        await model.signOut()
        XCTAssertEqual(accounts.writes, 0)
        XCTAssertEqual(accounts.authentications, 0)
        XCTAssertEqual(accounts.signOuts, 0)
        XCTAssertEqual(factory.preparations, 0)
    }

    func testParentsMustUnlockBeforePreferencesAndRelockRevokesEdits() {
        let model = KidsAppModel.preview("shows")
        let original = model.state?.preferences
        model.savePreferences(limit: 1, spoken: true)
        XCTAssertEqual(model.state?.preferences, original)
        XCTAssertFalse(model.unlock("0000"))
        XCTAssertTrue(model.unlock("4242"))
        model.savePreferences(limit: 1, spoken: true)
        XCTAssertEqual(model.state?.preferences.episodeLimit, 1)
        XCTAssertEqual(model.state?.preferences.spokenNavigation, true)
        model.lockParents()
        model.savePreferences(limit: 2, spoken: false)
        XCTAssertEqual(model.state?.preferences.episodeLimit, 1)
        XCTAssertEqual(model.state?.preferences.spokenNavigation, true)
    }

    func testSetNextChangesOnlyItsApprovedShow() async throws {
        let model = KidsAppModel.preview("again")
        let show = try XCTUnwrap(model.catalog[.shows]?.first)
        let episodes = try await model.episodes(for: show)
        let episode = try XCTUnwrap(episodes.first)
        let other = model.state?.ordered["show-2"]
        XCTAssertTrue(model.unlock("4242"))
        model.chooseNext(episode)
        XCTAssertEqual(model.state?.ordered[show.id]?.itemID, episode.id)
        XCTAssertEqual(model.state?.ordered[show.id]?.seconds, 0)
        XCTAssertEqual(model.state?.ordered["show-2"], other)
    }

    func testAuthorizationDenialClearsVisibleStateAndStopsPlayer() async {
        let model = KidsAppModel.preview("controls")
        XCTAssertNotNil(model.activePlayback)
        XCTAssertFalse(model.catalog.isEmpty)
        model.show(KidsAPIError.authentication)
        await drainIdentityDelivery()
        XCTAssertTrue(model.requiresParent)
        XCTAssertTrue(model.catalog.isEmpty)
        XCTAssertNil(model.selectedShow)
        XCTAssertNil(model.selectedMovie)
        XCTAssertNil(model.state)
        XCTAssertNil(model.activePlayback)
    }

    func testStalePresentationDismissalCannotStopReplacementSession() async throws {
        let model = KidsAppModel.preview("controls")
        let old = try XCTUnwrap(model.activePlayback)
        let title = try XCTUnwrap(model.catalog[.shows]?.first)
        let episodes = try await model.episodes(for: title)
        let replacement = KidsPlaybackController.preview(
            item: episodes[1],
            title: title,
            mode: .ordered,
            episodes: episodes,
            delegate: model,
            scenario: "controls"
        )
        model.activePlayback = replacement
        await model.dismissPlayback(old)
        XCTAssertTrue(model.activePlayback === replacement)
        await model.dismissPlayback(replacement)
        XCTAssertNil(model.activePlayback)
    }

    func testUnavailablePINLocksParentsWithoutCountingWrongPINOrWriting() {
        let accounts = Accounts(), factory = PlaybackFactory()
        accounts.savedPIN = "1234"
        accounts.pinReadFails = true
        let model = KidsAppModel(accounts: accounts, playbackFactory: factory)
        XCTAssertTrue(model.hasParentPIN)
        XCTAssertTrue(model.gate.attempt(correct: true, now: .now))
        XCTAssertFalse(model.unlock("1234"))
        XCTAssertFalse(model.unlocked)
        XCTAssertNotNil(model.parentPINProblem)
        XCTAssertEqual(model.gate.failures, 0)
        XCTAssertThrowsError(try model.setPIN("5678")) {
            XCTAssertEqual($0 as? KidsParentPINError, .unavailable)
        }
        XCTAssertEqual(accounts.writes, 0)
        XCTAssertEqual(accounts.savedPIN, "1234")
    }

    func testUnreadablePINBlocksSignInBeforeURLParsingOrHostAuthentication() async {
        let accounts = Accounts(), factory = PlaybackFactory()
        accounts.pinReadFails = true
        let model = KidsAppModel(accounts: accounts, playbackFactory: factory)
        for recovering in [false, true] {
            do {
                try await model.signIn(
                    urlText: "invalid URL",
                    username: "fixture",
                    password: "fixture",
                    parentPIN: "1234",
                    recovering: recovering
                )
                XCTFail("Unreadable credentials permitted sign-in")
            } catch { XCTAssertEqual(error as? KidsParentPINError, .unavailable) }
        }
        XCTAssertEqual(accounts.writes, 0)
        XCTAssertEqual(accounts.authentications, 0)
        XCTAssertEqual(factory.preparations, 0)
    }
}
