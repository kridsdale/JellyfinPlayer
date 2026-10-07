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

private enum ComponentFailure: Error { case update, reload, checkpoint }

@MainActor
private final class ComponentBinding {
    var current = true
    var checkpointCalls = 0
    var failCheckpoint: Int?
    func validate() throws {
        checkpointCalls += 1
        if checkpointCalls == failCheckpoint {
            throw ComponentFailure.checkpoint
        }
    }
}

@MainActor
private final class ComponentSender: JellyfinRequestSending {
    struct Call {
        let path: String
        let method: String
        let query: [(String, String?)]
        let body: Data?
    }

    var calls: [Call] = []
    var failure: ComponentFailure?
    var pauseUpdate = false
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
        if pauseUpdate {
            await withCheckedContinuation { pending = $0 }
        }
        if failure == .update {
            throw ComponentFailure.update
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
            throw ComponentFailure.reload
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
private func componentClient(_ sender: ComponentSender, _ binding: ComponentBinding) -> ItemMetadataClient {
    ItemMetadataClient(
        executor: .init(sender: sender, isCurrent: { binding.current }),
        userID: "fixture-user",
        bindingID: .init(transport: ObjectIdentifier(sender), userID: "fixture-user")
    )
}

@MainActor
private func settleComponent(_ predicate: () -> Bool) async throws {
    for _ in 0 ..< 2000 {
        if predicate() {
            return
        }
        await Task.yield()
    }
    try #require(predicate())
}

@Suite(.serialized) @MainActor
struct MetadataUpdateReloadContracts {
    @Test
    func `update preserves payload policy route and captured user`() async throws {
        let sender = ComponentSender(), binding = ComponentBinding(), client = componentClient(sender, binding)
        let edited = BaseItemDto(genres: ["Adventure"], id: "item", name: "Chosen title", tags: ["Kids"], trickplay: [:])
        let updated = try await client.updateAndReload(itemID: "item", item: edited, validate: binding.validate)
        #expect(updated.id == "item" && updated.name == "Fresh metadata")
        #expect(sender.calls.map(\.path) == ["/Items/item", "/Items/item"])
        #expect(sender.calls.map(\.method) == ["POST", "GET"] && binding.checkpointCalls == 3)
        #expect(sender.calls[1].query.contains { $0.0 == "userId" && $0.1 == "fixture-user" })
        let body = try #require(sender.calls.first?.body)
        let object = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(object["Id"] as? String == "item" && object["Name"] as? String == "Chosen title")
        #expect(object["Genres"] as? [String] == ["Adventure"] && object["Tags"] as? [String] == ["Kids"])
        #expect(object["Trickplay"] == nil && edited.trickplay != nil)
        #expect(Set(object.keys) == Set(["Id", "Name", "Genres", "Tags"]))
    }

    @Test
    func `update failure stops reload and original error survives`() async throws {
        let sender = ComponentSender(), binding = ComponentBinding(), client = componentClient(sender, binding)
        sender.failure = .update
        await #expect(throws: ComponentFailure.update) { try await client.updateAndReload(itemID: "item", item: .init(id: "item")) }
        #expect(sender.calls.count == 1 && sender.calls.first?.method == "POST")
    }

    @Test
    func `reload failure preserves accepted update and propagates without invented rollback`() async throws {
        let sender = ComponentSender(), binding = ComponentBinding(), client = componentClient(sender, binding)
        sender.failure = .reload
        await #expect(throws: ComponentFailure.reload) { try await client.updateAndReload(itemID: "item", item: .init(id: "item")) }
        #expect(sender.calls.map(\.method) == ["POST", "GET"])
    }

    @Test
    func `retired checkpoint rejects before update between stages and before return`() async throws {
        for stage in 1 ... 3 {
            let sender = ComponentSender(), binding = ComponentBinding(), client = componentClient(sender, binding)
            binding.failCheckpoint = stage
            await #expect(throws: ComponentFailure.checkpoint) {
                try await client.updateAndReload(itemID: "item", item: .init(id: "item"), validate: binding.validate)
            }
            #expect(sender.calls.count == stage - 1)
        }
    }

    @Test
    func `expired account while update ignores cancellation never starts reload`() async throws {
        let sender = ComponentSender(), binding = ComponentBinding(), client = componentClient(sender, binding)
        sender.pauseUpdate = true
        let task = Task { try await client.updateAndReload(itemID: "item", item: .init(id: "item")) }
        defer { task.cancel()
            sender.finish()
        }
        try await settleComponent { sender.pending != nil }
        binding.current = false
        sender.finish()
        let outcome = await task.result
        guard case let .failure(error) = outcome else { Issue.record("Expired account returned an item")
            return
        }
        #expect(error is CancellationError && sender.calls.count == 1)
    }

    @Test
    func `caller cancellation while update is pending does not read next stage`() async throws {
        let sender = ComponentSender(), binding = ComponentBinding(), client = componentClient(sender, binding)
        sender.pauseUpdate = true
        let task = Task { try await client.updateAndReload(itemID: "item", item: .init(id: "item")) }
        defer { task.cancel()
            sender.finish()
        }
        try await settleComponent { sender.pending != nil }
        task.cancel()
        sender.finish()
        let outcome = await task.result
        guard case let .failure(error) = outcome else { Issue.record("Cancelled update returned an item")
            return
        }
        #expect(error is CancellationError && sender.calls.count == 1)
    }

    @Test
    func `binding expiry during reload suppresses returned stale metadata`() async throws {
        let sender = ComponentSender(), binding = ComponentBinding(), client = componentClient(sender, binding)
        sender.pauseReload = true
        let task = Task { try await client.updateAndReload(itemID: "item", item: .init(id: "item")) }
        defer { task.cancel()
            sender.finish()
        }
        try await settleComponent { sender.pending != nil }
        binding.current = false
        sender.finish()
        let outcome = await task.result
        guard case let .failure(error) = outcome else { Issue.record("Expired reload returned an item")
            return
        }
        #expect(error is CancellationError && sender.calls.count == 2)
    }
}
