//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation
import Get
import SwiftfinNetworking
import Testing

private final class MetricsDelegate: NSObject, URLSessionDataDelegate {}
@MainActor
private final class MetricsBinding { var current = true }
@MainActor
private final class MetricsGate {
    var continuation: CheckedContinuation<Void, Never>?
    func wait() async {
        await withCheckedContinuation { continuation = $0 }
    }

    func finish() {
        continuation?.resume()
        continuation = nil
    }
}

private enum MetricsFailure: Error { case offline }
@MainActor
private class BasicMetricsSender: JellyfinRequestSending {
    var plainValues = 0, plainCommands = 0
    func value<Value: Decodable & Sendable>(for request: Request<Value>) async throws -> Value {
        plainValues += 1
        return try JSONDecoder().decode(Value.self, from: Data("7".utf8))
    }

    func complete(_ request: Request<Void>) async throws {
        plainCommands += 1
    }
}

@MainActor
private final class DelegateMetricsSender: JellyfinRequestSending {
    var delegateIDs: [ObjectIdentifier?] = []
    var plainCalls = 0
    var gate: MetricsGate?
    var fail = false
    func value<Value: Decodable & Sendable>(for request: Request<Value>) async throws -> Value {
        plainCalls += 1
        return try JSONDecoder().decode(Value.self, from: Data("7".utf8))
    }

    func complete(_ request: Request<Void>) async throws {
        plainCalls += 1
    }

    private func record(_ delegate: (any URLSessionDataDelegate)?) async throws {
        delegateIDs.append(delegate.map { ObjectIdentifier($0) })
        if let gate {
            await gate.wait()
        }
        if fail {
            throw MetricsFailure.offline
        }
    }

    func value<Value: Decodable & Sendable>(for request: Request<Value>, delegate: (any URLSessionDataDelegate)?) async throws -> Value {
        try await record(delegate)
        return try JSONDecoder().decode(Value.self, from: Data("7".utf8))
    }

    func complete(_ request: Request<Void>, delegate: (any URLSessionDataDelegate)?) async throws {
        try await record(delegate)
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

@Suite("Scoped request timing delegates")
@MainActor
struct ExecutorMetricsTests {
    @Test
    func `same delegate reaches value and command sender`() async throws {
        let sender = DelegateMetricsSender(), delegate = MetricsDelegate()
        let executor = AuthenticatedRequestExecutor(sender: sender)
        #expect(try await executor.value(for: Request<Int>(path: "/value", method: .get), delegate: delegate) == 7)
        try await executor.complete(Request<Void>(path: "/command", method: .post), delegate: delegate)
        #expect(sender.delegateIDs == [ObjectIdentifier(delegate), ObjectIdentifier(delegate)] && sender.plainCalls == 0)
    }

    @Test
    func `nil delegate and existing synthetic sender remain supported`() async throws {
        let sender = BasicMetricsSender()
        let executor = AuthenticatedRequestExecutor(sender: sender)
        #expect(try await executor.value(for: Request<Int>(path: "/value", method: .get), delegate: nil) == 7)
        try await executor.complete(Request<Void>(path: "/command", method: .post), delegate: nil)
        #expect(sender.plainValues == 1 && sender.plainCommands == 1)
    }

    @Test
    func `expired binding rejects timed IO before sender`() async {
        let sender = DelegateMetricsSender(), binding = MetricsBinding()
        binding.current = false
        let executor = AuthenticatedRequestExecutor(sender: sender, isCurrent: { binding.current })
        await #expect(throws: CancellationError.self) { try await executor.value(
            for: Request<Int>(path: "/value", method: .get),
            delegate: MetricsDelegate()
        ) }
        await #expect(throws: CancellationError.self) { try await executor.complete(
            Request<Void>(path: "/command", method: .post),
            delegate: MetricsDelegate()
        ) }
        #expect(sender.delegateIDs.isEmpty && sender.plainCalls == 0)
    }

    @Test
    func `late value and failed command respect replacement and cancellation`() async {
        for command in [false, true] {
            for cancelled in [false, true] {
                let sender = DelegateMetricsSender(), binding = MetricsBinding(), gate = MetricsGate()
                sender.gate = gate
                sender.fail = command
                let executor = AuthenticatedRequestExecutor(sender: sender, isCurrent: { binding.current })
                let task = Task {
                    if command {
                        try await executor.complete(Request<Void>(path: "/command", method: .post), delegate: MetricsDelegate())
                    } else {
                        _ = try await executor.value(for: Request<Int>(path: "/value", method: .get), delegate: MetricsDelegate())
                    }
                }
                await settle { gate.continuation != nil }
                if cancelled {
                    task.cancel()
                } else {
                    binding.current = false
                }
                gate.finish()
                await #expect(throws: CancellationError.self) { try await task.value }
                #expect(sender.delegateIDs.count == 1 && sender.plainCalls == 0)
            }
        }
    }

    @Test
    func `current timed transport error is preserved`() async {
        let sender = DelegateMetricsSender()
        sender.fail = true
        let executor = AuthenticatedRequestExecutor(sender: sender)
        await #expect(throws: MetricsFailure.self) { try await executor.complete(
            Request<Void>(path: "/command", method: .post),
            delegate: MetricsDelegate()
        ) }
    }
}
