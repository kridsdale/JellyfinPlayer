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
import SwiftfinServerOperations
import Testing

private enum ReplacementFailure: Error { case offline }
@MainActor
private final class ReplacementSender: JellyfinRequestSending {
    var calls: [(method: String, path: String, query: [(String, String?)])] = []
    var failAt: Int?
    var keys = Data(#"{"Items":[{"AppName":"z"},{"AppName":"A"}]}"#.utf8)
    private func capture(_ request: Request<some Any>) throws {
        calls.append((request.method.rawValue, request.url?.path ?? "", request.query ?? []))
        if calls.count == failAt {
            throw ReplacementFailure.offline
        }
    }

    func value<Value: Decodable & Sendable>(for request: Request<Value>) async throws -> Value {
        try capture(request)
        return try JSONDecoder().decode(Value.self, from: keys)
    }

    func complete(_ request: Request<Void>) async throws {
        try capture(request)
    }
}

@MainActor
private final class ReplacementState {
    var current = true
    var acknowledged = false
    var acknowledgedAfter = 0
}

@Suite(.serialized) @MainActor
struct KeyReplacementContracts {
    private func client(_ sender: ReplacementSender, _ state: ReplacementState) -> ServerOperationsClient {
        .init(executor: .init(sender: sender, isCurrent: { state.current }), deviceID: "synthetic")
    }

    @Test
    func `replacement acknowledges revoke before create and reloads the sorted keys`() async throws {
        let s = ReplacementSender(), state = ReplacementState()
        let result = try await client(s, state).replaceKey(name: "synthetic-app", token: "synthetic-token") {
            state.acknowledged = true
            state.acknowledgedAfter = s.calls.count
        }
        #expect(s.calls.map(\.method) == ["DELETE", "POST", "GET"])
        #expect(s.calls.map(\.path) == ["/Auth/Keys/synthetic-token", "/Auth/Keys", "/Auth/Keys"])
        #expect(s.calls[1].query.contains { $0.0 == "app" && $0.1 == "synthetic-app" })
        #expect(state.acknowledged && state.acknowledgedAfter == 1)
        #expect(result?.map(\.appName) == ["A", "z"])
    }

    @Test(arguments: [
        1,
        2,
        3
    ])
    func `partial failures preserve the revocation acknowledgement and stop subsequent commands`(_ failingCall: Int) async {
        let s = ReplacementSender(), state = ReplacementState()
        s.failAt = failingCall
        await #expect(throws: ReplacementFailure.self) {
            try await client(s, state).replaceKey(name: "app", token: "token") { state.acknowledged = true }
        }
        #expect(s.calls.count == failingCall && state.acknowledged == (failingCall > 1))
    }

    @Test
    func `null key list preserves the caller existing rows after revocation`() async throws {
        let s = ReplacementSender(), state = ReplacementState()
        s.keys = Data("{}".utf8)
        let result = try await client(s, state).replaceKey(name: "app", token: "token") { state.acknowledged = true }
        #expect(result == nil && state.acknowledged && s.calls.count == 3)
    }

    @Test
    func `account switch inside revocation receipt cannot create a key on the new account`() async {
        let s = ReplacementSender(), state = ReplacementState()
        await #expect(throws: CancellationError.self) {
            try await client(s, state).replaceKey(name: "app", token: "token") {
                state.acknowledged = true
                state.current = false
            }
        }
        #expect(state.acknowledged && s.calls.count == 1)
    }

    @Test
    func `already expired account starts no replacement and emits no receipt`() async {
        let s = ReplacementSender(), state = ReplacementState()
        state.current = false
        await #expect(throws: CancellationError.self) {
            try await client(s, state).replaceKey(name: "app", token: "token") { state.acknowledged = true }
        }
        #expect(s.calls.isEmpty && !state.acknowledged)
    }

    @Test
    func `task cancellation inside revocation receipt stops before creation`() async {
        let s = ReplacementSender(), state = ReplacementState()
        let task = Task {
            try await client(s, state).replaceKey(name: "app", token: "token") {
                state.acknowledged = true
                withUnsafeCurrentTask { $0?.cancel() }
            }
        }
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(state.acknowledged && s.calls.count == 1)
    }

    @Test
    func `creation preserves name and reloads sorted keys`() async throws {
        let s = ReplacementSender(), state = ReplacementState()
        let result = try await client(s, state).createKeyAndReload(name: "synthetic-app")
        #expect(s.calls.map(\.method) == ["POST", "GET"])
        #expect(s.calls.allSatisfy { $0.path == "/Auth/Keys" })
        #expect(s.calls[0].query.contains { $0.0 == "app" && $0.1 == "synthetic-app" })
        #expect(result?.map(\.appName) == ["A", "z"])
    }

    @Test
    func `creation with null list does not request a second list or invent rows`() async throws {
        let s = ReplacementSender(), state = ReplacementState()
        s.keys = Data("{}".utf8)
        #expect(try await client(s, state).createKeyAndReload(name: "") == nil)
        #expect(s.calls.count == 2)
    }

    @Test(arguments: [1, 2])
    func `creation and reload errors propagate without later requests`(_ failingCall: Int) async {
        let s = ReplacementSender(), state = ReplacementState()
        s.failAt = failingCall
        await #expect(throws: ReplacementFailure.self) { try await client(s, state).createKeyAndReload(name: "app") }
        #expect(s.calls.count == failingCall)
    }

    @Test
    func `creation with expired account sends no request`() async {
        let s = ReplacementSender(), state = ReplacementState()
        state.current = false
        await #expect(throws: CancellationError.self) { try await client(s, state).createKeyAndReload(name: "app") }
        #expect(s.calls.isEmpty)
    }
}
