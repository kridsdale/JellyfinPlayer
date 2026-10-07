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
import SwiftfinItemMetadata
import SwiftfinNetworking
import Testing

private enum IdentityFailure: Error { case apply, reload, checkpoint }

@MainActor
private final class IdentityBinding {
    var current = true
    var checkpointCalls = 0
    var failCheckpoint: Int?
    func validate() throws {
        checkpointCalls += 1
        if checkpointCalls == failCheckpoint {
            throw IdentityFailure.checkpoint
        }
    }
}

@MainActor
private final class IdentitySender: JellyfinRequestSending {
    struct Call {
        let path: String
        let method: String
        let query: [(String, String?)]
        let body: Data?
    }

    var calls: [Call] = []
    var failure: IdentityFailure?
    var pauseApply = false
    var pauseReload = false
    var pending: CheckedContinuation<Void, Never>?
    let response = Data("{\"Id\":\"item\",\"Name\":\"Fresh metadata\",\"Type\":\"Movie\"}".utf8)

    func complete(_ request: Request<Void>) async throws {
        try calls.append(.init(
            path: request.url?.path ?? "",
            method: request.method.rawValue,
            query: request.query ?? [],
            body: request.body.map { try JSONEncoder().encode($0) }
        ))
        if pauseApply {
            await withCheckedContinuation { pending = $0 }
        }
        if failure == .apply {
            throw IdentityFailure.apply
        }
    }

    func value<Value: Decodable & Sendable>(for request: Request<Value>) async throws -> Value {
        calls.append(.init(
            path: request.url?.path ?? "",
            method: request.method.rawValue,
            query: request.query ?? [],
            body: nil
        ))
        if pauseReload {
            await withCheckedContinuation { pending = $0 }
        }
        if failure == .reload {
            throw IdentityFailure.reload
        }
        return try JSONDecoder().decode(Value.self, from: response)
    }

    func finish() {
        let continuation = pending
        pending = nil
        continuation?.resume()
    }
}

@MainActor
private func identityClient(_ sender: IdentitySender, _ binding: IdentityBinding) -> ItemMetadataClient {
    ItemMetadataClient(
        executor: .init(sender: sender, isCurrent: { binding.current }),
        userID: "fixture-user",
        bindingID: .init(transport: ObjectIdentifier(sender), userID: "fixture-user")
    )
}

@MainActor
private func settleIdentity(_ predicate: () -> Bool) async throws {
    for _ in 0 ..< 2000 {
        if predicate() {
            return
        }
        await Task.yield()
    }
    try #require(predicate())
}

@Suite(.serialized) @MainActor
struct IdentityApplyReloadContracts {
    @Test
    func `apply route body and reload preserve captured item and user`() async throws {
        let sender = IdentitySender(), binding = IdentityBinding(), client = identityClient(sender, binding)
        let result = RemoteSearchResult(name: "Chosen identity", productionYear: 2001, providerIDs: ["Imdb": "fixture-id"])
        let updated = try await client.applyIdentityAndReload(itemID: "item", result: result, validate: binding.validate)
        #expect(updated.id == "item" && updated.name == "Fresh metadata")
        #expect(sender.calls.map(\.path) == ["/Items/RemoteSearch/Apply/item", "/Items/item"])
        #expect(sender.calls.map(\.method) == ["POST", "GET"] && binding.checkpointCalls == 3)
        #expect(sender.calls[1].query.contains { $0.0 == "userId" && $0.1 == "fixture-user" })
        let body = try #require(sender.calls.first?.body)
        let applied = try JSONDecoder().decode(RemoteSearchResult.self, from: body)
        #expect(applied.name == result.name && applied.providerIDs == result.providerIDs && applied.productionYear == 2001)
    }

    @Test
    func `apply failure stops reload and original error survives`() async throws {
        let sender = IdentitySender(), binding = IdentityBinding(), client = identityClient(sender, binding)
        sender.failure = .apply
        await #expect(throws: IdentityFailure.apply) { try await client.applyIdentityAndReload(itemID: "item", result: .init()) }
        #expect(sender.calls.count == 1 && sender.calls.first?.method == "POST")
    }

    @Test
    func `reload failure preserves accepted apply and propagates without invented rollback`() async throws {
        let sender = IdentitySender(), binding = IdentityBinding(), client = identityClient(sender, binding)
        sender.failure = .reload
        await #expect(throws: IdentityFailure.reload) { try await client.applyIdentityAndReload(itemID: "item", result: .init()) }
        #expect(sender.calls.map(\.method) == ["POST", "GET"])
    }

    @Test
    func `retired checkpoint rejects before apply between stages and before return`() async throws {
        for stage in 1 ... 3 {
            let sender = IdentitySender(), binding = IdentityBinding(), client = identityClient(sender, binding)
            binding.failCheckpoint = stage
            await #expect(throws: IdentityFailure.checkpoint) {
                try await client.applyIdentityAndReload(itemID: "item", result: .init(), validate: binding.validate)
            }
            #expect(sender.calls.count == stage - 1)
        }
    }

    @Test
    func `expired account while apply ignores cancellation never starts reload`() async throws {
        let sender = IdentitySender(), binding = IdentityBinding(), client = identityClient(sender, binding)
        sender.pauseApply = true
        let task = Task { try await client.applyIdentityAndReload(itemID: "item", result: .init()) }
        defer { task.cancel()
            sender.finish()
        }
        try await settleIdentity { sender.pending != nil }
        binding.current = false
        sender.finish()
        let outcome = await task.result
        guard case let .failure(error) = outcome else { Issue.record("Expired account returned an item")
            return
        }
        #expect(error is CancellationError && sender.calls.count == 1)
    }

    @Test
    func `caller cancellation while apply is pending does not read next stage`() async throws {
        let sender = IdentitySender(), binding = IdentityBinding(), client = identityClient(sender, binding)
        sender.pauseApply = true
        let task = Task { try await client.applyIdentityAndReload(itemID: "item", result: .init()) }
        defer { task.cancel()
            sender.finish()
        }
        try await settleIdentity { sender.pending != nil }
        task.cancel()
        sender.finish()
        let outcome = await task.result
        guard case let .failure(error) = outcome else { Issue.record("Cancelled apply returned an item")
            return
        }
        #expect(error is CancellationError && sender.calls.count == 1)
    }

    @Test
    func `binding expiry during reload suppresses returned stale metadata`() async throws {
        let sender = IdentitySender(), binding = IdentityBinding(), client = identityClient(sender, binding)
        sender.pauseReload = true
        let task = Task { try await client.applyIdentityAndReload(itemID: "item", result: .init()) }
        defer { task.cancel()
            sender.finish()
        }
        try await settleIdentity { sender.pending != nil }
        binding.current = false
        sender.finish()
        let outcome = await task.result
        guard case let .failure(error) = outcome else { Issue.record("Expired reload returned an item")
            return
        }
        #expect(error is CancellationError && sender.calls.count == 2)
    }
}
