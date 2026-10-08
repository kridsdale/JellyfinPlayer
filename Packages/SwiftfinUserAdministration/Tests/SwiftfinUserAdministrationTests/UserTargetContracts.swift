//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation
import Get
import JellyfinAPI
import SwiftfinNetworking
import SwiftfinUserAdministration
import Testing

@MainActor
private final class TargetBinding { var current = true }
@MainActor
private final class TargetSender: JellyfinRequestSending {
    struct Call { let path: String
        let method: String
        let userID: String?
        let body: Data?
    }

    var calls: [Call] = []
    var profile = UserDto(configuration: .init(myMediaExcludes: ["protected"]), id: "selected", name: "Original")
    var holdFirst = false
    var firstPending: CheckedContinuation<Void, Never>?
    private func record(_ request: Request<some Any>) throws {
        try calls.append(.init(
            path: request.url?.path ?? "",
            method: request.method.rawValue,
            userID: request.query?.first { $0.0 == "userId" }?.1,
            body: request.body.map { try JSONEncoder().encode($0) }
        ))
    }

    func value<Value: Decodable & Sendable>(for request: Request<Value>) async throws -> Value {
        try record(request)
        return try JSONDecoder().decode(Value.self, from: JSONEncoder().encode(profile))
    }

    func complete(_ request: Request<Void>) async throws {
        try record(request)
        if holdFirst, calls.count == 1 {
            await withCheckedContinuation { firstPending = $0 }
        }
        if request.url?.path == "/Users/selected/Policy", let body = calls.last?.body {
            profile.policy = try JSONDecoder().decode(UserPolicy.self, from: body)
        }
    }

    func release() {
        firstPending?.resume()
        firstPending = nil
    }
}

@MainActor
private func settleTarget(_ condition: () -> Bool) async {
    for _ in 0 ..< 2000 {
        if condition() {
            return
        }
        await Task.yield()
    }
    #expect(condition())
}

@Suite("Selected user and configuration ownership") @MainActor
struct UserTargetContracts {
    private func client(_ sender: TargetSender, binding: TargetBinding = .init()) -> UserAdministrationClient {
        .init(executor: .init(sender: sender, isCurrent: { binding.current }), currentUserID: "administrator")
    }

    private var policy: UserPolicy {
        .init(
            authenticationProviderID: "synthetic",
            enabledFolders: ["kids-only"],
            isAdministrator: false,
            passwordResetProviderID: "synthetic"
        )
    }

    @Test
    func `missing target and replaced account are rejected before any IO`() throws {
        let sender = TargetSender(), binding = TargetBinding(), client = client(sender, binding: binding)
        #expect(throws: UserAdministrationTarget.TargetError.self) { try client.target(userID: "") }
        let target = try client.target(userID: "selected")
        binding.current = false
        #expect(throws: CancellationError.self) { try target.checkBinding() }
        #expect(throws: CancellationError.self) { try client.target(userID: "selected") }
        #expect(sender.calls.isEmpty)
    }

    @Test
    func `selected user policy and rename never target authenticated administrator`() async throws {
        let sender = TargetSender(), target = try client(sender).target(userID: "selected")
        try await target.updatePolicy(policy)
        try await target.updateUsername("Renamed")
        #expect(sender.calls.map(\.path) == ["/Users/selected/Policy", "/Users/selected", "/Users"])
        #expect(sender.calls[0].path == "/Users/selected/Policy" && sender.calls[2].userID == "selected")
        let renamed = try JSONDecoder().decode(UserDto.self, from: #require(sender.calls.last?.body))
        #expect(renamed.id == "selected" && renamed.name == "Renamed")
        #expect(renamed.policy == policy && renamed.configuration?.myMediaExcludes == ["protected"])
    }

    @Test
    func `cancelled accepted policy drains before following rename reads fresh profile`() async throws {
        let sender = TargetSender()
        sender.holdFirst = true
        let target = try client(sender).target(userID: "selected")
        let first = Task { try await target.updatePolicy(policy) }
        await settleTarget { sender.firstPending != nil }
        first.cancel()
        let second = Task { try await target.updateUsername("After policy") }
        for _ in 0 ..< 30 {
            await Task.yield()
        }
        #expect(sender.calls.count == 1)
        sender.release()
        do { try await first.value
            Issue.record("Retired write unexpectedly succeeded")
        } catch is CancellationError {} catch {
            Issue.record("Unexpected failure: \(error)")
        }
        try await second.value
        let renamed = try JSONDecoder().decode(UserDto.self, from: #require(sender.calls.last?.body))
        #expect(sender.calls.count == 3 && renamed.policy == policy && renamed.name == "After policy")
    }

    @Test
    func `account replacement prevents queued rename and rejects accepted result`() async throws {
        let sender = TargetSender(), binding = TargetBinding()
        sender.holdFirst = true
        let target = try client(sender, binding: binding).target(userID: "selected")
        let first = Task { try await target.updatePolicy(policy) }
        await settleTarget { sender.firstPending != nil }
        let queued = Task { try await target.updateUsername("Never") }
        for _ in 0 ..< 20 {
            await Task.yield()
        }
        binding.current = false
        sender.release()
        for task in [first, queued] {
            do { try await task.value
                Issue.record("Replaced account accepted a result")
            } catch is CancellationError {} catch {
                Issue.record("Unexpected failure: \(error)")
            }
        }
        #expect(sender.calls.count == 1)
    }

    @Test
    func `wrong selected profile rejects reads and rename before mutation`() async throws {
        let sender = TargetSender()
        sender.profile.id = "different"
        let target = try client(sender).target(userID: "selected")
        await #expect(throws: CancellationError.self) { try await target.user() }
        await #expect(throws: CancellationError.self) { try await target.updateUsername("Never") }
        #expect(sender.calls.count == 2 && sender.calls.allSatisfy { $0.method == "GET" })
    }

    @Test
    func `settings and Auto Play share ordering and retain sibling preferences`() async throws {
        let sender = TargetSender()
        sender.holdFirst = true
        let updates = client(sender).configurationUpdates(userID: "selected")
        var snapshot = UserConfiguration(audioLanguagePreference: "en", enableNextEpisodeAutoPlay: false, myMediaExcludes: ["kids-only"])
        var completions = 0
        try updates.submit(snapshot, completion: { completions += 1 })
        await settleTarget { sender.firstPending != nil }
        snapshot.subtitleLanguagePreference = "fr"
        try updates.submit(snapshot, completion: { completions += 1 })
        try updates.toggle(from: snapshot, willSubmit: { snapshot = $0 })
        for _ in 0 ..< 20 {
            await Task.yield()
        }
        #expect(sender.calls.count == 1)
        sender.release()
        await updates.waitUntilFinished()
        #expect(sender.calls.count == 2 && completions == 0)
        let final = try JSONDecoder().decode(UserConfiguration.self, from: #require(sender.calls.last?.body))
        #expect(final.enableNextEpisodeAutoPlay == true && final.audioLanguagePreference == "en")
        #expect(final.subtitleLanguagePreference == "fr" && final.myMediaExcludes == ["kids-only"])
        #expect(sender.calls.allSatisfy { $0.userID == "selected" })
    }

    @Test
    func `only current completed configuration calls its completion receipt`() async throws {
        let sender = TargetSender(), updates = client(sender).configurationUpdates()
        var completions = 0
        try updates.submit(.init(audioLanguagePreference: "en"), completion: { completions += 100 })
        try updates.submit(.init(audioLanguagePreference: "fr"), completion: { completions += 1 })
        await updates.waitUntilFinished()
        #expect(completions == 1 && sender.calls.count == 1)
    }
}
