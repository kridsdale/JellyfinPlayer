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
import Testing

private enum StubError: Error { case offline }
@MainActor
private final class Gate {
    var continuation: CheckedContinuation<Void, Never>?
    func wait() async {
        await withCheckedContinuation { continuation = $0 }
    }

    func finish() {
        continuation?.resume()
        continuation = nil
    }
}

@MainActor
private final class Binding { var current = true }
private struct Captured {
    let path: String
    let method: String
    let query: [String: String]
    let body: Data?
}

@MainActor
private final class Sender: JellyfinRequestSending {
    var calls: [Captured] = []
    var responses: [String: Data] = [:]
    var gate: Gate?
    var failure = false
    private func capture(_ request: Request<some Any>) throws {
        let pairs = (request.query ?? []).compactMap { k, v in v.map { (k, $0) } }
        try calls.append(.init(
            path: request.url?.path ?? "",
            method: request.method.rawValue,
            query: Dictionary(grouping: pairs, by: { $0.0 }).mapValues { $0.map(\.1).joined(separator: ",") },
            body: request.body.map { try JSONEncoder().encode($0) }
        ))
    }

    func value<Value: Decodable & Sendable>(for request: Request<Value>) async throws -> Value {
        try capture(request)
        if let gate {
            await gate.wait()
        }
        if failure {
            throw StubError.offline
        }
        let data = responses[request.url?.path ?? ""] ?? Data((String(describing: Value.self).hasPrefix("Array<") ? "[]" : "{}").utf8)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(Value.self, from: data)
    }

    func complete(_ request: Request<Void>) async throws {
        try capture(request)
        if let gate {
            await gate.wait()
        }
        if failure {
            throw StubError.offline
        }
    }
}

@MainActor
private func settle(_ condition: () -> Bool) async {
    for _ in 0 ..< 2000 {
        if condition() {
            return
        }
        await Task.yield()
    }
    #expect(condition())
}

import SwiftfinUserAdministration

@Suite("Server user administration")
@MainActor
struct UserAdministrationTests {
    private func client(_ sender: Sender) -> UserAdministrationClient {
        .init(executor: .init(sender: sender), currentUserID: "self")
    }

    @Test
    func `self deletion is excluded and duplicates are coalesced`() async throws {
        let s = Sender()
        let deleted = try await client(s).deleteUsers(ids: ["self", "other", "other", "second"])
        #expect(deleted == ["other", "second"])
        #expect(s.calls.count == 2)
        #expect(Set(s.calls.map(\.path)) == ["/Users/other", "/Users/second"])
        #expect(s.calls.allSatisfy { $0.method == "DELETE" })
    }

    @Test
    func `empty or self only batch does no IO`() async throws {
        let s = Sender()
        let c = client(s)
        #expect(try await c.deleteUsers(ids: []).isEmpty)
        #expect(try await c.deleteUsers(ids: ["self"]).isEmpty)
        #expect(s.calls.isEmpty)
    }

    @Test
    func `missing or disabled filter does not restrict to opposite state`() async throws {
        #expect(UserAdministrationClient.filterValue(false) == nil && UserAdministrationClient.filterValue(true) == true)
        let s = Sender()
        let c = client(s)
        _ = try await c.users()
        _ = try await c.users(isHidden: true, isDisabled: true)
        #expect(s.calls[0].query.isEmpty)
        #expect(s.calls[1].query["isHidden"] == "true" && s.calls[1].query["isDisabled"] == "true")
    }

    @Test
    func `user ordering retains nil last`() {
        #expect(UserAdministrationClient.sortedUsers([.init(id: "nil"), .init(id: "b", name: "B"), .init(id: "a", name: "A")])
            .map(\.id) == [
                "a",
                "b",
                "nil"
            ])
    }

    @Test
    func `all account operations preserve identifiers and payloads`() async throws {
        let s = Sender()
        let c = client(s)
        _ = try await c.user(id: "selected")
        _ = try await c.create(name: "Kid", password: "synthetic")
        _ = try await c.libraries(isHidden: false)
        try await c.updatePolicy(
            id: "selected",
            policy: .init(authenticationProviderID: "synthetic", isAdministrator: false, passwordResetProviderID: "synthetic")
        )
        try await c.updateConfiguration(id: "selected", configuration: .init(myMediaExcludes: ["excluded"]))
        try await c.updateUser(id: "selected", user: .init(id: "selected", name: "New"))
        #expect(s.calls.count == 6)
        #expect(s.calls[0].path == "/Users/selected" && s.calls[0].method == "GET")
        #expect(s.calls[1].path == "/Users/New" && s.calls[1].method == "POST")
        #expect(s.calls[2].query["isHidden"] == "false")
        #expect(s.calls[3].path == "/Users/selected/Policy" && s.calls[4].path == "/Users/Configuration" && s.calls[4]
            .query["userId"] == "selected")
        let object = try JSONSerialization.jsonObject(with: #require(s.calls[4].body)) as? [String: Any]
        #expect(object?["MyMediaExcludes"] as? [String] == ["excluded"])
    }

    @Test
    func `failure does not claim successful batch`() async {
        let s = Sender()
        s.failure = true
        await #expect(throws: StubError.self) { try await client(s).deleteUsers(ids: ["other"]) }
    }

    @Test
    func `binding replacement rejects late user response`() async {
        let s = Sender()
        let b = Binding()
        let gate = Gate()
        s.gate = gate
        let c = UserAdministrationClient(executor: .init(sender: s, isCurrent: { b.current }), currentUserID: "self")
        let task = Task { try await c.user(id: "selected") }
        await settle { gate.continuation != nil }
        b.current = false
        gate.finish()
        await #expect(throws: CancellationError.self) { try await task.value }
    }
}
