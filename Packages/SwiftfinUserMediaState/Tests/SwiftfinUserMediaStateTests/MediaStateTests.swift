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
import SwiftfinUserMediaState
import Testing

@MainActor
private final class Binding { var current = true }
@MainActor
private final class Sender: JellyfinRequestSending {
    struct Call { let path: String
        let method: String
        let userID: String?
    }

    var calls: [Call] = []
    var response = UserItemDataDto(isFavorite: true, isPlayed: true, itemID: "item", key: "key")
    var failure = false
    var blocked = false
    var gate: CheckedContinuation<Void, Never>?
    enum Failure: Error { case offline }
    func value<Value: Decodable & Sendable>(for request: Request<Value>) async throws -> Value {
        calls.append(.init(
            path: request.url?.path ?? "",
            method: request.method.rawValue,
            userID: request.query?.first(where: { $0.0 == "userId" })?.1
        ))
        if blocked {
            await withCheckedContinuation { gate = $0 }
        }
        if failure {
            throw Failure.offline
        }
        let data = try JSONEncoder().encode(response)
        return try JSONDecoder().decode(Value.self, from: data)
    }

    func complete(_ request: Request<Void>) async throws {
        throw Failure.offline
    }

    func release() {
        blocked = false
        gate?.resume()
        gate = nil
    }

    func wait(for count: Int) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while calls.count < count || (blocked && gate == nil) {
            if .now >= deadline {
                throw Failure.offline
            }
            await Task.yield()
        }
    }
}

@MainActor
private func make(_ sender: Sender, _ binding: Binding = Binding()) -> UserMediaStateClient {
    .init(executor: .init(sender: sender, isCurrent: { binding.current }), userID: "user")
}

@Test @MainActor
func `all four exact user scoped commands`() async throws {
    let sender = Sender()
    let client = make(sender)
    for field in [UserMediaStateField.played, .favorite] {
        for value in [true, false] {
            let result = try await client.set(field, value: value, itemID: "item")
            #expect(result.itemID == "item")
        }
    }
    #expect(sender.calls.map(\.path) == [
        "/UserPlayedItems/item",
        "/UserPlayedItems/item",
        "/UserFavoriteItems/item",
        "/UserFavoriteItems/item"
    ])
    #expect(sender.calls.map(\.method) == ["POST", "DELETE", "POST", "DELETE"])
    #expect(sender.calls.allSatisfy { $0.userID == "user" })
}

@Test @MainActor
func `expired account does not issue commands`() async {
    let sender = Sender()
    let binding = Binding()
    let client = make(sender, binding)
    binding.current = false
    await #expect(throws: CancellationError.self) { try await client.set(.played, value: true, itemID: "item") }
    #expect(sender.calls.isEmpty)
}

@Test @MainActor
func `replaced account rejects late success and queued command`() async throws {
    let sender = Sender()
    sender.blocked = true
    let binding = Binding()
    let client = make(sender, binding)
    let first = Task { @MainActor in try await client.set(.played, value: true, itemID: "item") }
    try await sender.wait(for: 1)
    let second = Task { @MainActor in try await client.set(.favorite, value: true, itemID: "item") }
    await Task.yield()
    binding.current = false
    sender.release()
    await #expect(throws: CancellationError.self) { try await first.value }
    await #expect(throws: CancellationError.self) { try await second.value }
    #expect(sender.calls.count == 1)
}

@Test @MainActor
func `replaced account normalizes late failure to cancellation`() async throws {
    let sender = Sender()
    sender.blocked = true
    sender.failure = true
    let binding = Binding()
    let client = make(sender, binding)
    let task = Task { @MainActor in try await client.set(.played, value: false, itemID: "item") }
    try await sender.wait(for: 1)
    binding.current = false
    sender.release()
    await #expect(throws: CancellationError.self) { try await task.value }
}

@Test @MainActor
func `current failure remains available for optimistic rollback`() async {
    let sender = Sender()
    sender.failure = true
    let client = make(sender)
    await #expect(throws: Sender.Failure.self) { try await client.set(.favorite, value: true, itemID: "item") }
}

@Test @MainActor
func `mismatched response cannot publish to selected item`() async {
    let sender = Sender()
    sender.response.itemID = "different"
    let client = make(sender)
    await #expect(throws: UserMediaStateError.self) { try await client.set(.played, value: true, itemID: "item") }
}

@Test @MainActor
func `legacy response without item ID remains accepted`() async throws {
    let sender = Sender()
    sender.response.itemID = nil
    let client = make(sender)
    let result = try await client.set(.favorite, value: false, itemID: "item")
    #expect(result.itemID == nil)
}

@Test @MainActor
func `serial commands cannot overtake an older mutation`() async throws {
    let sender = Sender()
    sender.blocked = true
    let client = make(sender)
    let first = Task { @MainActor in try await client.set(.played, value: true, itemID: "item") }
    try await sender.wait(for: 1)
    let second = Task { @MainActor in try await client.set(.played, value: false, itemID: "item") }
    for _ in 0 ..< 20 {
        await Task.yield()
    }
    #expect(sender.calls.count == 1)
    sender.release()
    _ = try await first.value
    _ = try await second.value
    #expect(sender.calls.map(\.method) == ["POST", "DELETE"])
}

@Test @MainActor
func `caller cancellation drops A queued command before IO`() async throws {
    let sender = Sender()
    sender.blocked = true
    let client = make(sender)
    let first = Task { @MainActor in try await client.set(.played, value: true, itemID: "item") }
    try await sender.wait(for: 1)
    let second = Task { @MainActor in try await client.set(.favorite, value: true, itemID: "item") }
    await Task.yield()
    second.cancel()
    sender.release()
    _ = try await first.value
    await #expect(throws: CancellationError.self) { try await second.value }
    #expect(sender.calls.count == 1)
}

@Test @MainActor
func `mutation epochs reject old completion without invalidating other field`() {
    let sequence = UserMediaMutationSequence()
    let first = sequence.begin(itemID: "item", field: .played)
    let favorite = sequence.begin(itemID: "item", field: .favorite)
    let latest = sequence.begin(itemID: "item", field: .played)
    #expect(!sequence.accepts(first, currentItemID: "item"))
    #expect(sequence.accepts(latest, currentItemID: "item"))
    #expect(sequence.accepts(favorite, currentItemID: "item"))
    #expect(!sequence.accepts(latest, currentItemID: "other"))
    sequence.invalidate()
    #expect(!sequence.accepts(latest, currentItemID: "item"))
    #expect(!sequence.accepts(favorite, currentItemID: "item"))
}

@Test
func `response merge does not overwrite other optimistic field`() {
    let current = UserItemDataDto(isFavorite: false, isPlayed: false, itemID: "item", key: "before", rating: 7)
    let response = UserItemDataDto(
        isFavorite: true,
        isPlayed: true,
        itemID: "item",
        key: "after",
        playCount: 2,
        playbackPositionTicks: 0,
        playedPercentage: 100
    )
    let played = UserMediaStatePolicy.merge(response, into: current, field: .played)
    #expect(played.isPlayed == true)
    #expect(played.isFavorite == false)
    #expect(played.playCount == 2)
    #expect(played.playbackPositionTicks == 0)
    #expect(played.playedPercentage == 100)
    #expect(played.rating == 7)
    let favorite = UserMediaStatePolicy.merge(response, into: current, field: .favorite)
    #expect(favorite.isFavorite == true)
    #expect(favorite.isPlayed == false)
    #expect(favorite.playCount == nil)
    #expect(UserMediaStatePolicy.merge(response, into: nil, field: .favorite) == response)
}
