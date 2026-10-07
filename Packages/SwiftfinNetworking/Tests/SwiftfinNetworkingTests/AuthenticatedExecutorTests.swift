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

    func response<Value: Decodable & Sendable>(for request: Request<Value>) async throws -> JellyfinResponse<Value> {
        try await .init(value: value(for: request), responseURL: URL(string: "https://redirect.example/base"))
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

@Suite("Authenticated request binding")
@MainActor
struct AuthenticatedExecutorTests {
    @Test
    func `expired binding rejects both ports before IO`() async {
        let sender = Sender()
        let executor = AuthenticatedRequestExecutor(sender: sender, isCurrent: { false })
        await #expect(throws: CancellationError.self) { try await executor.value(for: Request<String>(path: "/read")) }
        await #expect(throws: CancellationError.self) { try await executor.complete(Request<Void>(path: "/command", method: .post)) }
        #expect(sender.calls.isEmpty)
    }

    @Test(arguments: [false, true])
    func `replaced binding rejects late success and error`(_ failure: Bool) async {
        let sender = Sender()
        let binding = Binding()
        let gate = Gate()
        sender.gate = gate
        sender.failure = failure
        sender.responses["/read"] = try? JSONEncoder().encode("value")
        let executor = AuthenticatedRequestExecutor(sender: sender, isCurrent: { binding.current })
        let task = Task { try await executor.value(for: Request<String>(path: "/read")) }
        await settle { gate.continuation != nil }
        binding.current = false
        gate.finish()
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(sender.calls.count == 1)
    }

    @Test(arguments: [false, true])
    func `canceled command rejects late success and error`(_ failure: Bool) async {
        let sender = Sender()
        let gate = Gate()
        sender.gate = gate
        sender.failure = failure
        let executor = AuthenticatedRequestExecutor(sender: sender)
        let task = Task { try await executor.complete(Request<Void>(path: "/command", method: .post)) }
        await settle { gate.continuation != nil }
        task.cancel()
        gate.finish()
        await #expect(throws: CancellationError.self) { try await task.value }
    }

    @Test(arguments: [false, true])
    func `replaced command rejects late success and error`(_ failure: Bool) async {
        let sender = Sender()
        let binding = Binding()
        let gate = Gate()
        sender.gate = gate
        sender.failure = failure
        let executor = AuthenticatedRequestExecutor(sender: sender, isCurrent: { binding.current })
        let task = Task { try await executor.complete(Request<Void>(path: "/command", method: .post)) }
        await settle { gate.continuation != nil }
        binding.current = false
        gate.finish()
        await #expect(throws: CancellationError.self) { try await task.value }
    }

    @Test
    func `current transport error propagates`() async {
        let sender = Sender()
        sender.failure = true
        let executor = AuthenticatedRequestExecutor(sender: sender)
        await #expect(throws: StubError.self) { try await executor.value(for: Request<String>(path: "/read")) }
    }

    @Test
    func `exact injected sender is retained for both ports`() async throws {
        let first = Sender()
        let other = Sender()
        first.responses["/read"] = try JSONEncoder().encode("first")
        let executor = AuthenticatedRequestExecutor(sender: first)
        let value = try await executor.value(for: Request<String>(path: "/read"))
        #expect(value == "first")
        try await executor.complete(Request<Void>(path: "/command", method: .post))
        #expect(first.calls.map(\.path) == ["/read", "/command"] && other.calls.isEmpty)
    }
}

@Test @MainActor
func `metadata response preserves value and URL`() async throws {
    let sender = Sender()
    sender.responses["/read"] = try JSONEncoder().encode("value")
    let executor = AuthenticatedRequestExecutor(sender: sender)
    let result = try await executor.response(for: Request<String>(path: "/read"))
    #expect(result.value == "value")
    #expect(result.responseURL?.absoluteString == "https://redirect.example/base")
}

@Test @MainActor
func `obsolete metadata response rejected before IO`() async {
    let sender = Sender()
    let executor = AuthenticatedRequestExecutor(sender: sender, isCurrent: { false })
    await #expect(throws: CancellationError.self) { try await executor.response(for: Request<String>(path: "/read")) }
    #expect(sender.calls.isEmpty)
}

@Test(arguments: [false, true]) @MainActor
func `replaced metadata response rejects late success and failure`(_ failure: Bool) async {
    let sender = Sender()
    let binding = Binding()
    let gate = Gate()
    sender.gate = gate
    sender.failure = failure
    sender.responses["/read"] = try? JSONEncoder().encode("value")
    let executor = AuthenticatedRequestExecutor(sender: sender, isCurrent: { binding.current })
    let task = Task { try await executor.response(for: Request<String>(path: "/read")) }
    await settle { gate.continuation != nil }
    binding.current = false
    gate.finish()
    await #expect(throws: CancellationError.self) { try await task.value }
}

@Test @MainActor
func `metadata response current error is preserved`() async {
    let sender = Sender()
    sender.failure = true
    let executor = AuthenticatedRequestExecutor(sender: sender)
    await #expect(throws: StubError.self) { try await executor.response(for: Request<String>(path: "/read")) }
}
