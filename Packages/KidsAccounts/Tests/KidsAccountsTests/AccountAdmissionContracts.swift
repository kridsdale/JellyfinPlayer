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
private final class AdmissionHost: KidsAccountHost {
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

    var beforeSignOut: (@MainActor () async -> Void)?
    func signOut(validate: @escaping KidsAccountCheckpoint) async throws {
        try validate()
        await beforeSignOut?()
        try validate()
        changes.send(nil)
    }
}

@MainActor
private final class AdmissionPause {
    var continuation: CheckedContinuation<Void, Never>?
    var effects = 0
    func wait() async {
        await withCheckedContinuation { continuation = $0 }
    }

    func resume() {
        let old = continuation
        continuation = nil
        old?.resume()
    }
}

@Suite(.serialized) @MainActor
struct AccountAdmissionContracts {
    private func identity(
        user: String = "child",
        token: String = "fixture",
        name: String = "Fixture",
        url: String = "http://server.test"
    ) -> KidsAccountIdentity {
        .init(serverURL: URL(string: url)!, serverID: "server", serverName: name, userID: user, accessToken: token)
    }

    private let binding = KidsBinding(serverID: "server", userID: "child", showsID: "tv", moviesID: "movies")

    @Test
    func `replacement cancellation and owner release revoke pending attempts`() throws {
        let host = AdmissionHost()
        var owner: KidsAccountAdmission? = KidsAccountAdmission(host: host)
        let first = try #require(owner).begin()
        let second = try #require(owner).begin()
        #expect(throws: CancellationError.self) { try first.check() }
        try second.check()
        owner?.cancel()
        #expect(throws: CancellationError.self) { try second.check() }
        let third = try #require(owner).begin()
        owner = nil
        #expect(throws: CancellationError.self) { try third.check() }
    }

    @Test
    func `identity ABA cannot revive admission while display renaming stays valid`() throws {
        let host = AdmissionHost()
        host.changes.send(identity())
        let owner = KidsAccountAdmission(host: host)
        let attempt = try owner.begin()
        host.changes.send(identity(name: "Renamed"))
        try attempt.check()
        host.changes.send(identity(token: "replacement"))
        host.changes.send(identity())
        #expect(throws: CancellationError.self) { try attempt.check() }
    }

    @Test
    func `a cancelled submission does not replace the active attempt`() async throws {
        let owner = KidsAccountAdmission(host: AdmissionHost())
        let active = try owner.begin()
        let task = Task { try owner.begin() }
        task.cancel()
        do { _ = try await task.value
            Issue.record("Cancelled submission replaced admission")
        } catch { #expect(error is CancellationError) }
        try active.check()
    }

    @Test
    func `retired admission cannot reach credential storage`() throws {
        let host = AdmissionHost(), pause = AdmissionPause()
        let owner = KidsAccountAdmission(host: host), attempt = try owner.begin()
        let account = KidsAuthenticatedAccount(identity: identity(), credentialStorage: { _ in pause.effects += 1 }) { _ in }
        owner.cancel()
        #expect(throws: CancellationError.self) { try attempt.prepare(account, binding: binding) }
        #expect(pause.effects == 0)
    }

    @Test
    func `credential replacement admits its exact identity and activation is consumed once`() async throws {
        let host = AdmissionHost(), pause = AdmissionPause()
        host.changes.send(identity(token: "old"))
        let owner = KidsAccountAdmission(host: host), attempt = try owner.begin()
        let target = identity()
        let account = KidsAuthenticatedAccount(identity: target, credentialStorage: { validate in
            try validate()
            host.changes.send(target)
            try validate()
        }) { validate in
            try validate()
            pause.effects += 1
        }
        try attempt.prepare(account, binding: binding)
        try await attempt.activate(account, binding: binding)
        #expect(host.currentIdentity == target && pause.effects == 1)
        do { try await attempt.activate(account, binding: binding)
            Issue.record("Consumed preparation was replayed")
        } catch { #expect(error as? KidsContractError == .denied) }
        #expect(pause.effects == 1)
    }

    @Test
    func `storage callback reentry revokes subsequent effects and preparation`() async throws {
        let host = AdmissionHost(), pause = AdmissionPause()
        let owner = KidsAccountAdmission(host: host), attempt = try owner.begin()
        let account = KidsAuthenticatedAccount(identity: identity(), credentialStorage: { validate in
            pause.effects += 1
            owner.cancel()
            try validate()
            pause.effects += 1
        }) { _ in pause.effects += 100 }
        #expect(throws: CancellationError.self) { try attempt.prepare(account, binding: binding) }
        #expect(pause.effects == 1, "Already accepted effects are not undone")
        do { try await account.activate(binding: binding)
            Issue.record("Revoked preparation activated")
        } catch { #expect(error as? KidsContractError == .denied) }
        #expect(pause.effects == 1)
    }

    @Test
    func `late noncooperating activation checks admission before its effect`() async throws {
        let host = AdmissionHost(), pause = AdmissionPause()
        let owner = KidsAccountAdmission(host: host), attempt = try owner.begin()
        let account = KidsAuthenticatedAccount(identity: identity()) { validate in
            await pause.wait()
            try validate()
            pause.effects += 1
            host.changes.send(self.identity())
        }
        try attempt.prepare(account, binding: binding)
        let task = Task { try await attempt.activate(account, binding: binding) }
        for _ in 0 ..< 100 where pause.continuation == nil {
            await Task.yield()
        }
        _ = try #require(pause.continuation)
        host.changes.send(identity(user: "other"))
        pause.resume()
        do { try await task.value
            Issue.record("Obsolete activation returned success")
        } catch { #expect(error is CancellationError) }
        #expect(pause.effects == 0)
    }

    @Test
    func `activation cannot succeed without the exact published identity`() async throws {
        let host = AdmissionHost()
        let owner = KidsAccountAdmission(host: host), attempt = try owner.begin()
        let account = KidsAuthenticatedAccount(identity: identity()) { validate in try validate() }
        try attempt.prepare(account, binding: binding)
        do { try await attempt.activate(account, binding: binding)
            Issue.record("Missing account publication was accepted")
        } catch { #expect(error as? KidsContractError == .denied) }
    }

    @Test
    func `sign out admits nil identity and retires earlier sign in`() async throws {
        let host = AdmissionHost()
        host.changes.send(identity())
        let owner = KidsAccountAdmission(host: host)
        let earlier = try owner.begin()
        let logout = try owner.begin()
        try await logout.signOut()
        #expect(host.currentIdentity == nil)
        #expect(throws: CancellationError.self) { try earlier.check() }
    }

    @Test
    func `late sign out cannot clear a newer admitted account`() async throws {
        let host = AdmissionHost(), pause = AdmissionPause()
        host.changes.send(identity(token: "old"))
        host.beforeSignOut = { await pause.wait() }
        let owner = KidsAccountAdmission(host: host), logout = try owner.begin()
        let task = Task { try await logout.signOut() }
        for _ in 0 ..< 100 where pause.continuation == nil {
            await Task.yield()
        }
        _ = try #require(pause.continuation)
        let next = try owner.begin(), target = identity()
        let account = KidsAuthenticatedAccount(identity: target) { validate in
            try validate()
            host.changes.send(target)
        }
        try next.prepare(account, binding: binding)
        try await next.activate(account, binding: binding)
        pause.resume()
        do { try await task.value
            Issue.record("Late logout cleared replacement account")
        } catch { #expect(error is CancellationError) }
        #expect(host.currentIdentity == target)
    }
}
