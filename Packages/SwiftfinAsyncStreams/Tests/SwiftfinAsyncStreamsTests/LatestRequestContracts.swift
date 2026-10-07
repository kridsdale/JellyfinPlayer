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

    @Test
    func `replacement cancellation reentry retains the newest request and never starts its obsolete competitor`() async throws {
        let gate = LatestRequestGate(), trace = LatestRequestTrace(), owner = LatestRequest<Int>()
        defer { owner.cancel()
            gate.finishAll()
        }
        owner.replace(operation: {
            try await withTaskCancellationHandler {
                try await gate.load(1)
            } onCancel: { [weak owner] in
                MainActor.assumeIsolated {
                    owner?.replace(operation: { try await gate.load(3) }, receive: trace.append)
                }
            }
        }, receive: trace.append)
        try await settleLatestRequest { gate.pending[1] != nil }
        owner.replace(operation: { try await gate.load(2) }, receive: trace.append)
        try await settleLatestRequest { gate.pending[3] != nil }
        #expect(gate.pending[2] == nil)
        gate.finish(3, value: 300)
        try await settleLatestRequest { gate.completed[3] != nil }
        #expect(trace.values == [300])
        gate.finish(1, value: 100)
    }

    @Test
    func `cancel cleanup reentry leaves its newly created task owned and cancellable`() async throws {
        let gate = LatestRequestGate(), trace = LatestRequestTrace(), owner = LatestRequest<Int>()
        defer { owner.cancel()
            gate.finishAll()
        }
        owner.replace(operation: {
            try await withTaskCancellationHandler {
                try await gate.load(1)
            } onCancel: { [weak owner] in
                MainActor.assumeIsolated {
                    owner?.replace(operation: { try await gate.load(3) }, receive: trace.append)
                }
            }
        }, receive: trace.append)
        try await settleLatestRequest { gate.pending[1] != nil }
        owner.cancel()
        try await settleLatestRequest { gate.pending[3] != nil }
        owner.cancel()
        gate.finish(3, value: 300)
        try await settleLatestRequest { gate.completed[3] != nil }
        #expect(gate.completed[3] == true && trace.values.isEmpty)
        gate.finish(1, value: 100)
    }
}

extension LatestRequestContracts {
    @Test
    func `begin is synchronous and can cancel before IO`() async {
        let owner = LatestRequest<Int>(), trace = LatestRequestTrace()
        var began = false
        owner.replace(operation: { trace.attempts += 1
            return 1
        }, begin: {
            began = true
            owner.cancel()
        }, receive: trace.append)
        #expect(began)
        await owner.waitUntilFinished()
        #expect(trace.attempts == 0 && trace.values.isEmpty)
    }

    @Test
    func `begin reentry starts only the newest request`() async {
        let owner = LatestRequest<Int>(), trace = LatestRequestTrace()
        owner.replace(operation: { trace.attempts += 1
            return 1
        }, begin: {
            owner.replace(operation: { trace.attempts += 1
                return 2
            }, receive: trace.append)
        }, receive: trace.append)
        await owner.waitUntilFinished()
        #expect(trace.attempts == 1 && trace.values == [2])
    }

    @Test
    func `current failure callback runs on owner actor and can retry`() async throws {
        let owner = LatestRequest<Int>(), trace = LatestRequestTrace()
        var failures = 0
        owner.replace(operation: { throw LatestRequestGate.Failure.unavailable }, failure: { error in
            MainActor.preconditionIsolated()
            #expect(error is LatestRequestGate.Failure)
            failures += 1
            owner.replace(operation: { 2 }, receive: trace.append)
        }, receive: trace.append)
        try await settleLatestRequest { trace.values == [2] }
        #expect(failures == 1)
    }

    @Test
    func `obsolete failure cannot reach failure callback or retire newer work`() async throws {
        let owner = LatestRequest<Int>(), gate = LatestRequestGate(), trace = LatestRequestTrace()
        var failures = 0
        defer { owner.cancel()
            gate.finishAll()
        }
        owner.replace(operation: { try await gate.load(1) }, failure: { _ in failures += 1 }, receive: trace.append)
        try await settleLatestRequest { gate.pending[1] != nil }
        owner.replace(operation: { try await gate.load(2) }, failure: { _ in failures += 1 }, receive: trace.append)
        try await settleLatestRequest { gate.pending[2] != nil }
        gate.fail(1)
        gate.finish(2, value: 2)
        await owner.waitUntilFinished()
        #expect(failures == 0 && trace.values == [2])
    }

    @Test
    func `explicit cancellation and transport cancellation remain quiet`() async {
        let owner = LatestRequest<Int>(), trace = LatestRequestTrace()
        var failures = 0
        for kind in 0 ..< 2 {
            owner.replace(operation: {
                if kind == 0 {
                    throw CancellationError()
                }
                throw URLError(.cancelled)
            }, failure: { _ in failures += 1 }, receive: trace.append)
            await owner.waitUntilFinished()
        }
        #expect(failures == 0 && trace.values.isEmpty)
        owner.replace(operation: { 3 }, receive: trace.append)
        await owner.waitUntilFinished()
        #expect(trace.values == [3])
    }

    @Test
    func `wait captures entry request rather than a later replacement`() async throws {
        let owner = LatestRequest<Int>(), gate = LatestRequestGate(), trace = LatestRequestTrace()
        var finished = false
        defer { owner.cancel()
            gate.finishAll()
        }
        owner.replace(operation: { try await gate.load(1) }, receive: trace.append)
        try await settleLatestRequest { gate.pending[1] != nil }
        let waiter = Task { @MainActor in
            await owner.waitUntilFinished()
            finished = true
        }
        // Give the waiter the actor before submitting the replacement.
        for _ in 0 ..< 20 {
            await Task.yield()
        }
        owner.replace(operation: { try await gate.load(2) }, receive: trace.append)
        try await settleLatestRequest { gate.pending[2] != nil }
        #expect(!finished)
        gate.finish(1, value: 1)
        await waiter.value
        #expect(finished && gate.pending[2] != nil && trace.values.isEmpty)
        gate.finish(2, value: 2)
        await owner.waitUntilFinished()
        #expect(trace.values == [2])
    }
}

extension LatestRequestContracts {
    @Test
    func `cancelled submission preserves already active request`() async throws {
        let owner = LatestRequest<Int>(), gate = LatestRequestGate(), trace = LatestRequestTrace()
        defer { owner.cancel()
            gate.finishAll()
        }
        owner.replace(operation: { try await gate.load(1) }, receive: trace.append)
        try await settleLatestRequest { gate.pending[1] != nil }
        let cancelled = Task { @MainActor in
            withUnsafeCurrentTask { $0?.cancel() }
            owner.replace(operation: { 2 }, begin: { trace.attempts += 1 }, receive: trace.append)
        }
        await cancelled.value
        gate.finish(1, value: 1)
        await owner.waitUntilFinished()
        #expect(gate.completed[1] == false && trace.values == [1] && trace.attempts == 0)
    }
}
