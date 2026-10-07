//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Combine
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
        let account = KidsAuthenticatedAccount(identity: identity()) { _ in activated = true }
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
        let account = KidsAuthenticatedAccount(identity: identity()) { _ in throw ActivationFailure() }
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
        let account = KidsAuthenticatedAccount(identity: identity(), credentialStorage: { _ in stored = true }) { _ in activated = true }
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
        let account = KidsAuthenticatedAccount(identity: identity(), credentialStorage: { _ in throw StorageFailure() }) { _ in
            activated = true
        }
        let binding = KidsBinding(serverID: "server", userID: "child", showsID: "tv", moviesID: "movies")
        XCTAssertThrowsError(try account.prepareActivation(binding: binding)) { XCTAssertTrue($0 is StorageFailure) }
        do {
            try await account.activate(binding: binding)
            XCTFail("Failed credential storage activated the account")
        } catch { XCTAssertEqual(error as? KidsContractError, .denied) }
        XCTAssertFalse(activated)
    }
}

@MainActor
private final class ParentPINHost: KidsAccountHost {
    struct StorageFailure: Error {}
    var savedPIN: String?
    var readFails = false
    var writeFails = false
    var writes = 0
    var currentIdentity: KidsAccountIdentity? {
        nil
    }

    var identityChanges: AnyPublisher<KidsAccountIdentity?, Never> {
        Just(nil).eraseToAnyPublisher()
    }

    var parentPIN: String? {
        get throws {
            if readFails {
                throw StorageFailure()
            }
            return savedPIN
        }
    }

    func storeParentPIN(_ pin: String) throws {
        writes += 1
        if writeFails {
            throw StorageFailure()
        }
        savedPIN = pin
    }

    func authenticate(
        url: URL,
        serverID: String,
        serverName: String,
        username: String,
        password: String
    ) async throws -> KidsAuthenticatedAccount {
        throw KidsContractError.denied
    }

    func signOut(validate: @escaping KidsAccountCheckpoint) async throws {
        try validate()
    }
}

extension KidsAccountHostTests {
    @MainActor
    func testUnreadablePINUsesExistingPINRouteAndPreservesHostError() {
        let host = ParentPINHost()
        XCTAssertFalse(host.hasParentPIN)
        host.savedPIN = "1234"
        XCTAssertTrue(host.hasParentPIN)
        host.readFails = true
        XCTAssertTrue(host.hasParentPIN)
        XCTAssertThrowsError(try host.parentPIN) { XCTAssertTrue($0 is ParentPINHost.StorageFailure) }
        XCTAssertEqual(host.writes, 0)
    }

    @MainActor
    func testParentPINComparisonRequiresAStoredPIN() throws {
        let host = ParentPINHost()
        XCTAssertFalse(try host.matchesParentPIN(""))
        XCTAssertFalse(try host.matchesParentPIN("1234"))
        host.savedPIN = "1234"
        XCTAssertFalse(try host.matchesParentPIN("4321"))
        XCTAssertTrue(try host.matchesParentPIN("1234"))
        XCTAssertEqual(host.writes, 0)
    }

    @MainActor
    func testFirstParentPINRequiresSuccessfulStorage() throws {
        let host = ParentPINHost()
        try host.authorizeParentSetup(unlocked: false)
        try host.replaceParentPIN("1234", unlocked: false)
        XCTAssertEqual(host.savedPIN, "1234")
        XCTAssertEqual(host.writes, 1)
    }

    @MainActor
    func testReplacementRequiresCurrentParentAuthority() throws {
        let host = ParentPINHost()
        host.savedPIN = "1234"
        XCTAssertThrowsError(try host.replaceParentPIN("5678", unlocked: false)) {
            XCTAssertEqual($0 as? KidsContractError, .denied)
        }
        XCTAssertEqual(host.savedPIN, "1234")
        XCTAssertEqual(host.writes, 0)
        try host.replaceParentPIN("5678", unlocked: true)
        XCTAssertEqual(host.savedPIN, "5678")
        XCTAssertEqual(host.writes, 1)
    }

    @MainActor
    func testInvalidPINCannotReachCredentialWriter() throws {
        let host = ParentPINHost()
        for pin in ["", "123", "123456789", "12ab", "12 4", "12\n4"] {
            XCTAssertThrowsError(try host.replaceParentPIN(pin, unlocked: false)) {
                XCTAssertEqual($0 as? KidsContractError, .denied)
            }
        }
        XCTAssertNil(host.savedPIN)
        XCTAssertEqual(host.writes, 0)
        try host.replaceParentPIN("12345678", unlocked: false)
        XCTAssertEqual(host.savedPIN, "12345678")
    }

    @MainActor
    func testReadFailureDeniesSetupMatchingAndReplacementIncludingRecovery() {
        let host = ParentPINHost()
        host.savedPIN = "1234"
        host.readFails = true
        for unlocked in [false, true] {
            for recovering in [false, true] {
                XCTAssertThrowsError(try host.authorizeParentSetup(unlocked: unlocked, recovering: recovering)) {
                    XCTAssertEqual($0 as? KidsParentPINError, .unavailable)
                }
            }
            XCTAssertThrowsError(try host.replaceParentPIN("5678", unlocked: unlocked)) {
                XCTAssertEqual($0 as? KidsParentPINError, .unavailable)
            }
        }
        XCTAssertThrowsError(try host.matchesParentPIN("1234")) {
            XCTAssertEqual($0 as? KidsParentPINError, .unavailable)
        }
        XCTAssertEqual(host.savedPIN, "1234")
        XCTAssertEqual(host.writes, 0)
    }

    @MainActor
    func testWriteFailureCannotReportSuccessfulSetupOrReplacement() {
        let host = ParentPINHost()
        host.writeFails = true
        XCTAssertThrowsError(try host.replaceParentPIN("1234", unlocked: false)) {
            XCTAssertEqual($0 as? KidsParentPINError, .unavailable)
        }
        XCTAssertNil(host.savedPIN)
        host.savedPIN = "1234"
        XCTAssertThrowsError(try host.replaceParentPIN("5678", unlocked: true)) {
            XCTAssertEqual($0 as? KidsParentPINError, .unavailable)
        }
        XCTAssertEqual(host.savedPIN, "1234")
        XCTAssertEqual(host.writes, 2)
    }

    @MainActor
    func testRecoveryAdmissionDoesNotAuthorizePINReplacement() throws {
        let host = ParentPINHost()
        host.savedPIN = "1234"
        try host.authorizeParentSetup(unlocked: false, recovering: true)
        XCTAssertThrowsError(try host.replaceParentPIN("5678", unlocked: false)) {
            XCTAssertEqual($0 as? KidsContractError, .denied)
        }
        XCTAssertEqual(host.savedPIN, "1234")
        XCTAssertEqual(host.writes, 0)
    }
}

extension KidsAccountHostTests {
    @MainActor
    func testFailedPreparationRevokesEarlierPreparedBinding() async throws {
        struct RetryFailure: Error {}
        let flags = AdmissionRetryFlags()
        let account = KidsAuthenticatedAccount(identity: identity(), credentialStorage: { _ in
            if flags.fail {
                throw RetryFailure()
            }
        }) { _ in flags.activated = true }
        let binding = KidsBinding(serverID: "server", userID: "child", showsID: "tv", moviesID: "movies")
        try account.prepareActivation(binding: binding)
        flags.fail = true
        XCTAssertThrowsError(try account.prepareActivation(binding: binding))
        do {
            try await account.activate(binding: binding)
            XCTFail("Failed retry retained earlier preparation authority")
        } catch { XCTAssertEqual(error as? KidsContractError, .denied) }
        XCTAssertFalse(flags.activated)
    }
}

@MainActor
private final class AdmissionRetryFlags {
    var fail = false
    var activated = false
}
