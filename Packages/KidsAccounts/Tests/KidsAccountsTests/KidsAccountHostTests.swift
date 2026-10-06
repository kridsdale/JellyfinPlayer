//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation
@testable import KidsAccounts
import KidsDomain
import XCTest

final class KidsAccountHostTests: XCTestCase {
    private func identity(
        url: String = "http://server.test:8096",
        server: String = "server",
        user: String = "child",
        token: String = "synthetic-token"
    ) -> KidsAccountIdentity {
        .init(serverURL: URL(string: url)!, serverID: server, serverName: "Test server", userID: user, accessToken: token)
    }

    func testFullIdentityChangesForCredentialsServerURLAndAccount() {
        let original = identity()
        XCTAssertEqual(original, identity())
        let renamed = KidsAccountIdentity(
            serverURL: original.serverURL,
            serverID: original.serverID,
            serverName: "Renamed server",
            userID: original.userID,
            accessToken: original.accessToken
        )
        XCTAssertEqual(original, renamed, "Display metadata must not cancel an authorized playback identity")
        XCTAssertEqual(Set([original, renamed]).count, 1)
        XCTAssertNotEqual(original, identity(token: "replacement-token"))
        XCTAssertNotEqual(original, identity(url: "http://another.test:8096"))
        XCTAssertNotEqual(original, identity(server: "replacement-server"))
        XCTAssertNotEqual(original, identity(user: "another-child"))
    }

    func testIdentityDescriptionsRedactCredentialsAndHouseholdDetails() {
        let value = identity()
        for output in [String(describing: value), String(reflecting: value)] {
            XCTAssertFalse(output.contains(value.accessToken))
            XCTAssertFalse(output.contains(value.serverURL.absoluteString))
            XCTAssertFalse(output.contains(value.userID))
            XCTAssertEqual(output, "KidsAccountIdentity(redacted)")
        }
    }

    @MainActor
    func testAuthenticationDoesNotActivateBeforeVerifiedBinding() async throws {
        var activated = false
        let account = KidsAuthenticatedAccount(identity: identity()) { activated = true }
        XCTAssertFalse(activated)
        for binding in [
            KidsBinding(serverID: "wrong", userID: "child", showsID: "tv", moviesID: "movies"),
            KidsBinding(serverID: "server", userID: "wrong", showsID: "tv", moviesID: "movies"),
            KidsBinding(serverID: "server", userID: "child", showsID: "same", moviesID: "same"),
            KidsBinding(serverID: "server", userID: "child", showsID: "", moviesID: "movies")
        ] {
            do {
                try await account.activate(binding: binding)
                XCTFail("Invalid binding activated the account")
            } catch {
                XCTAssertEqual(error as? KidsContractError, .denied)
                XCTAssertFalse(activated)
            }
        }
        let binding = KidsBinding(serverID: "server", userID: "child", showsID: "tv", moviesID: "movies")
        try account.prepareActivation(binding: binding)
        XCTAssertFalse(activated)
        try await account.activate(binding: binding)
        XCTAssertTrue(activated)
    }

    @MainActor
    func testActivationFailureRemainsVisibleToApplication() async throws {
        struct ActivationFailure: Error {}
        let account = KidsAuthenticatedAccount(identity: identity()) { throw ActivationFailure() }
        try account.prepareActivation(binding: .init(serverID: "server", userID: "child", showsID: "tv", moviesID: "movies"))
        do {
            try await account.activate(binding: .init(serverID: "server", userID: "child", showsID: "tv", moviesID: "movies"))
            XCTFail("Activation error was lost")
        } catch { XCTAssertTrue(error is ActivationFailure) }
    }
}

extension KidsAccountHostTests {
    @MainActor
    func testPreparedAccountCannotActivateAnotherLibraryBinding() async throws {
        var stored = false
        var activated = false
        let account = KidsAuthenticatedAccount(identity: identity(), credentialStorage: { stored = true }) { activated = true }
        let binding = KidsBinding(serverID: "server", userID: "child", showsID: "tv", moviesID: "movies")
        try account.prepareActivation(binding: binding)
        XCTAssertTrue(stored)
        XCTAssertFalse(activated)
        do {
            try await account.activate(binding: .init(serverID: "server", userID: "child", showsID: "other-tv", moviesID: "movies"))
            XCTFail("Swapped library binding activated the account")
        } catch { XCTAssertEqual(error as? KidsContractError, .denied) }
        XCTAssertFalse(activated)
    }

    @MainActor
    func testFailedCredentialStorageCannotActivateAccount() async throws {
        struct StorageFailure: Error {}
        var activated = false
        let account = KidsAuthenticatedAccount(identity: identity(), credentialStorage: { throw StorageFailure() }) { activated = true }
        let binding = KidsBinding(serverID: "server", userID: "child", showsID: "tv", moviesID: "movies")
        XCTAssertThrowsError(try account.prepareActivation(binding: binding)) { XCTAssertTrue($0 is StorageFailure) }
        do {
            try await account.activate(binding: binding)
            XCTFail("Failed credential storage activated the account")
        } catch { XCTAssertEqual(error as? KidsContractError, .denied) }
        XCTAssertFalse(activated)
    }
}
