//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation
import SwiftfinAsyncStreams
import Testing

@MainActor
private final class LatestRequestGate {
    var pending: [Int: CheckedContinuation<Int, any Error>] = [:]
    var completed: [Int: Bool] = [:]

    func load(_ id: Int) async throws -> Int {
        let value = try await withCheckedThrowingContinuation { pending[id] = $0 }
        completed[id] = Task.isCancelled
        return value // Deliberately ignores cancellation; the owner must discard it.
    }

    func finish(_ id: Int, value: Int) {
        pending.removeValue(forKey: id)?.resume(returning: value)
    }

    func fail(_ id: Int) {
        pending.removeValue(forKey: id)?.resume(throwing: Failure.unavailable)
    }

    func finishAll() {
        let continuations = pending.values
        pending.removeAll()
        for continuation in continuations {
            continuation.resume(throwing: CancellationError())
        }
    }

    enum Failure: Error { case unavailable }
}

@MainActor
private final class LatestRequestTrace {
    var values: [Int] = []
    var attempts = 0
    func append(_ value: Int) {
        MainActor.preconditionIsolated()
        values.append(value)
    }
}

@MainActor
private func settleLatestRequest(_ predicate: () -> Bool) async throws {
    for _ in 0 ..< 2000 {
        if predicate() {
            return
        }
        await Task.yield()
    }
    try #require(predicate())
}

@MainActor
struct LatestRequestContracts {
    @Test
    func `replacement publishes only the newest noncooperating response`() async throws {
        let gate = LatestRequestGate(), trace = LatestRequestTrace(), owner = LatestRequest<Int>()
        defer { owner.cancel()
            gate.finishAll()
        }
        owner.replace(operation: { try await gate.load(1) }, receive: trace.append)
        try await settleLatestRequest { gate.pending[1] != nil }
        owner.replace(operation: { try await gate.load(2) }, receive: trace.append)
        try await settleLatestRequest { gate.pending[2] != nil }
        gate.finish(2, value: 200)
        try await settleLatestRequest { trace.values == [200] }
        gate.finish(1, value: 100)
        try await settleLatestRequest { gate.completed[1] != nil }
        #expect(gate.completed[1] == true && gate.completed[2] == false)
        #expect(trace.values == [200])
    }

    @Test
    func `cancel is immediate idempotent and permits a later request`() async throws {
        let gate = LatestRequestGate(), trace = LatestRequestTrace(), owner = LatestRequest<Int>()
        defer { owner.cancel()
            gate.finishAll()
        }
        owner.replace(operation: { try await gate.load(1) }, receive: trace.append)
        try await settleLatestRequest { gate.pending[1] != nil }
        owner.cancel()
        owner.cancel()
        gate.finish(1, value: 100)
        try await settleLatestRequest { gate.completed[1] != nil }
        #expect(trace.values.isEmpty && gate.completed[1] == true)
        owner.replace(operation: { 200 }, receive: trace.append)
        try await settleLatestRequest { trace.values == [200] }
    }

    @Test
    func `release cancels a pending operation without retaining the owner`() async throws {
        let gate = LatestRequestGate(), trace = LatestRequestTrace()
        var owner: LatestRequest<Int>? = LatestRequest()
        weak let weakOwner = owner
        defer { gate.finishAll() }
        owner?.replace(operation: { try await gate.load(1) }, receive: trace.append)
        try await settleLatestRequest { gate.pending[1] != nil }
        owner = nil
        #expect(weakOwner == nil)
        gate.finish(1, value: 100)
        try await settleLatestRequest { gate.completed[1] != nil }
        #expect(gate.completed[1] == true && trace.values.isEmpty)
    }

    @Test
    func `cancel before execution performs no operation`() async {
        let trace = LatestRequestTrace(), owner = LatestRequest<Int>()
        owner.replace(operation: { trace.attempts += 1
            return 100
        }, receive: trace.append)
        owner.cancel()
        for _ in 0 ..< 20 {
            await Task.yield()
        }
        #expect(trace.attempts == 0 && trace.values.isEmpty)
    }

    @Test
    func `failure publishes nothing and does not prevent retry`() async throws {
        let gate = LatestRequestGate(), trace = LatestRequestTrace(), owner = LatestRequest<Int>()
        defer { owner.cancel()
            gate.finishAll()
        }
        owner.replace(operation: { try await gate.load(1) }, receive: trace.append)
        try await settleLatestRequest { gate.pending[1] != nil }
        gate.fail(1)
        owner.replace(operation: { 200 }, receive: trace.append)
        try await settleLatestRequest { trace.values == [200] }
        #expect(trace.values == [200])
    }

    @Test
    func `reentrant publication can replace the request without losing its lease`() async throws {
        let gate = LatestRequestGate(), trace = LatestRequestTrace(), owner = LatestRequest<Int>()
        defer { owner.cancel()
            gate.finishAll()
        }
        owner.replace(operation: { 100 }) { [weak owner] value in
            trace.append(value)
            owner?.replace(operation: { try await gate.load(2) }, receive: trace.append)
        }
        try await settleLatestRequest { gate.pending[2] != nil }
        owner.cancel()
        gate.finish(2, value: 200)
        try await settleLatestRequest { gate.completed[2] != nil }
        #expect(trace.values == [100] && gate.completed[2] == true)
    }

    @Test
    func `separate owners do not cancel each others requests`() async throws {
        let gate = LatestRequestGate(), trace = LatestRequestTrace()
        let first = LatestRequest<Int>(), second = LatestRequest<Int>()
        defer { first.cancel()
            second.cancel()
            gate.finishAll()
        }
        first.replace(operation: { try await gate.load(1) }, receive: trace.append)
        second.replace(operation: { try await gate.load(2) }, receive: trace.append)
        try await settleLatestRequest { gate.pending.count == 2 }
        first.cancel()
        gate.finish(2, value: 200)
        try await settleLatestRequest { trace.values == [200] }
        gate.finish(1, value: 100)
        try await settleLatestRequest { gate.completed[1] != nil }
        #expect(gate.completed[2] == false && trace.values == [200])
    }

    @Test
    func `late failure from a replaced request cannot retire the current lease`() async throws {
        let gate = LatestRequestGate(), trace = LatestRequestTrace(), owner = LatestRequest<Int>()
        defer { owner.cancel()
            gate.finishAll()
        }
        owner.replace(operation: { try await gate.load(1) }, receive: trace.append)
        try await settleLatestRequest { gate.pending[1] != nil }
        owner.replace(operation: { try await gate.load(2) }, receive: trace.append)
        try await settleLatestRequest { gate.pending[2] != nil }
        gate.fail(1)
        for _ in 0 ..< 20 {
            await Task.yield()
        }
        owner.cancel()
        gate.finish(2, value: 200)
        try await settleLatestRequest { gate.completed[2] != nil }
        #expect(trace.values.isEmpty && gate.completed[2] == true)
    }
}
