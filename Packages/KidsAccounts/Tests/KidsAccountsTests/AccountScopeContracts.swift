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
import KidsDomain
import Testing

@MainActor
private final class ScopeHost: KidsAccountHost {
    let changes = CurrentValueSubject<KidsAccountIdentity?, Never>(nil)
    var currentIdentity: KidsAccountIdentity? {
        changes.value
    }

    var identityChanges: AnyPublisher<KidsAccountIdentity?, Never> {
        changes.eraseToAnyPublisher()
    }

    var parentPIN: String? {
        nil
    }

    func storeParentPIN(_ pin: String) throws {}
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
        changes.send(nil)
    }
}

@MainActor
struct AccountScopeContracts {
    private func identity(token: String = "synthetic", name: String = "Fixture", user: String = "kid") -> KidsAccountIdentity {
        .init(serverURL: URL(string: "http://example.test")!, serverID: "server", serverName: name, userID: user, accessToken: token)
    }

    @Test
    func `duplicate publication and display rename retain the same account authority`() throws {
        let host = ScopeHost(), scope = KidsAccountScope(host: host)
        host.changes.send(identity())
        let lease = scope.capture()
        host.changes.send(identity())
        host.changes.send(identity(name: "Renamed"))
        #expect(lease.isCurrent)
        try lease.check()
    }

    @Test
    func `credential replacement permanently retires the original lease through ABA`() {
        let host = ScopeHost(), scope = KidsAccountScope(host: host)
        host.changes.send(identity())
        let old = scope.capture()
        host.changes.send(identity(token: "replacement"))
        host.changes.send(identity())
        #expect(!old.isCurrent)
        #expect(throws: CancellationError.self) { try old.check() }
        #expect(scope.capture().isCurrent)
    }

    @Test
    func `logout and a different account retire prior work even when the old user returns`() {
        let host = ScopeHost(), scope = KidsAccountScope(host: host)
        host.changes.send(identity())
        let beforeLogout = scope.capture()
        host.changes.send(nil)
        let signedOut = scope.capture()
        host.changes.send(identity(user: "other"))
        host.changes.send(identity())
        #expect(!beforeLogout.isCurrent && !signedOut.isCurrent && scope.capture().isCurrent)
    }

    @Test
    func `retained receipt does not keep its authority owner alive`() throws {
        let host = ScopeHost()
        var scope: KidsAccountScope? = KidsAccountScope(host: host)
        let isReleased = { [weak scope] in scope == nil }
        let lease = try #require(scope?.capture())
        scope = nil
        #expect(isReleased() && !lease.isCurrent)
        #expect(throws: CancellationError.self) { try lease.check() }
    }

    @Test
    func `cancelled actions fail while same account final checkpoints retain authority`() async {
        let host = ScopeHost(), scope = KidsAccountScope(host: host)
        let lease = scope.capture()
        let task = Task { @MainActor in
            #expect(lease.isCurrent)
            #expect(throws: CancellationError.self) { try lease.check() }
        }
        task.cancel()
        await task.value
        #expect(lease.isCurrent)
    }

    @Test
    func `suspended action cannot publish effects after credential replacement`() async {
        let host = ScopeHost(), scope = KidsAccountScope(host: host)
        host.changes.send(identity())
        let lease = scope.capture()
        let ready = AsyncStream<Void>.makeStream()
        let resume = AsyncStream<Void>.makeStream()
        var effects = 0
        let task = Task { @MainActor in
            ready.continuation.yield(())
            for await _ in resume.stream {
                break
            }
            do { try lease.check()
                effects += 1
            } catch { #expect(error is CancellationError) }
        }
        for await _ in ready.stream {
            break
        }
        host.changes.send(identity(token: "replacement"))
        resume.continuation.yield(())
        await task.value
        #expect(effects == 0)
        ready.continuation.finish()
        resume.continuation.finish()
    }
}
