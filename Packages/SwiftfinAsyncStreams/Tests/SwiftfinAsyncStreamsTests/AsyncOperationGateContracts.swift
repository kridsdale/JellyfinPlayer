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
private final class OperationSuspension {
    var pending: [Int: CheckedContinuation<Int, Never>] = [:]
    func read(_ id: Int) async -> Int {
        await withCheckedContinuation { pending[id] = $0 }
    }

    func finish(_ id: Int, value: Int) {
        pending.removeValue(forKey: id)?.resume(returning: value)
    }

    func clean() {
        let values = Array(pending.values)
        pending.removeAll()
        for value in values {
            value.resume(returning: -1)
        }
    }
}

@MainActor
private final class OperationEffects {
    var values: [Int] = []
    func append(_ value: Int) {
        MainActor.preconditionIsolated()
        values.append(value)
    }
}

@MainActor
private func settleOperation(_ predicate: () -> Bool) async throws {
    for _ in 0 ..< 2000 {
        if predicate() {
            return
        }
        await Task.yield()
    }
    try #require(predicate())
}

@Suite(.serialized) @MainActor
struct AsyncOperationGateContracts {
    @Test
    func `current checkpoint remains valid for multiple guarded effects`() throws {
        let owner = AsyncOperationGate(), effects = OperationEffects()
        let validate = owner.begin()
        try validate()
        effects.append(1)
        try validate()
        effects.append(2)
        #expect(effects.values == [1, 2])
    }

    @Test
    func `equal A B A inputs cannot revive earlier queued intent`() throws {
        let owner = AsyncOperationGate()
        let oldA = owner.begin(), b = owner.begin(), newA = owner.begin()
        #expect(throws: CancellationError.self) { try oldA() }
        #expect(throws: CancellationError.self) { try b() }
        try newA()
    }

    @Test
    func `retirement is immediate idempotent and permits a later intent`() throws {
        let owner = AsyncOperationGate(), old = owner.begin()
        owner.cancel()
        owner.cancel()
        #expect(throws: CancellationError.self) { try old() }
        let replacement = owner.begin()
        try replacement()
        #expect(throws: CancellationError.self) { try old() }
    }

    @Test
    func `queued checkpoint does not retain its released owner`() throws {
        var owner: AsyncOperationGate? = AsyncOperationGate()
        let reference = { [weak owner] in owner }
        let validate = try #require(owner).begin()
        owner = nil
        #expect(reference() == nil)
        #expect(throws: CancellationError.self) { try validate() }
    }

    @Test
    func `caller cancellation rejects a noncooperating awaited value`() async throws {
        let owner = AsyncOperationGate(), suspension = OperationSuspension(), effects = OperationEffects()
        let validate = owner.begin()
        let task = Task { @MainActor in
            let value = await suspension.read(1)
            do { try validate()
                effects.append(value)
                return true
            } catch is CancellationError { return false }
            catch { return true }
        }
        defer { task.cancel()
            suspension.clean()
        }
        try await settleOperation { suspension.pending[1] != nil }
        task.cancel()
        suspension.finish(1, value: 100)
        let committed = await task.value
        #expect(!committed && effects.values.isEmpty)
    }

    @Test
    func `obsolete noncooperating read cannot overwrite a newer result`() async throws {
        let owner = AsyncOperationGate(), suspension = OperationSuspension(), effects = OperationEffects()
        let first = owner.begin()
        let old = Task { @MainActor in
            let value = await suspension.read(1)
            do { try first()
                effects.append(value)
                return true
            } catch { return false }
        }
        try await settleOperation { suspension.pending[1] != nil }
        let second = owner.begin()
        let latest = Task { @MainActor in
            let value = await suspension.read(2)
            do { try second()
                effects.append(value)
                return true
            } catch { return false }
        }
        defer { old.cancel()
            latest.cancel()
            suspension.clean()
        }
        try await settleOperation { suspension.pending[2] != nil }
        suspension.finish(2, value: 200)
        let newestCommitted = await latest.value
        suspension.finish(1, value: 100)
        let oldCommitted = await old.value
        #expect(newestCommitted && !oldCommitted && effects.values == [200])
        #expect(!old.isCancelled) // Relevance is independent of cooperative cancellation.
    }

    @Test
    func `checkpoint prevents the next stage without undoing committed work`() async throws {
        let owner = AsyncOperationGate(), suspension = OperationSuspension(), effects = OperationEffects()
        let validate = owner.begin()
        let task = Task { @MainActor in
            do {
                try validate()
                effects.append(1)
                _ = await suspension.read(1)
                try validate()
                effects.append(2)
                return true
            } catch { return false }
        }
        defer { task.cancel()
            suspension.clean()
        }
        try await settleOperation { suspension.pending[1] != nil }
        owner.cancel()
        suspension.finish(1, value: 0)
        let finished = await task.value
        #expect(!finished && effects.values == [1])
    }

    @Test
    func `synchronous notification reentry suppresses the obsolete final event`() throws {
        let owner = AsyncOperationGate(), effects = OperationEffects()
        let first = owner.begin()
        try first()
        effects.append(1) // A notification has already been delivered.
        let replacement = owner.begin() // Its subscriber submits a newer operation.
        do { try first()
            effects.append(2)
        } catch is CancellationError {}
        try replacement()
        effects.append(3)
        #expect(effects.values == [1, 3])
    }

    @Test
    func `debounced A B A keeps newest equal input and rejects an earlier pending A`() async throws {
        let owner = AsyncOperationGate(), suspension = OperationSuspension(), effects = OperationEffects()
        let deliveredA = owner.begin()
        let old = Task { @MainActor in
            let value = await suspension.read(1)
            do { try deliveredA()
                effects.append(value)
                return true
            } catch { return false }
        }
        defer { old.cancel()
            suspension.clean()
        }
        try await settleOperation { suspension.pending[1] != nil }
        let undeliveredB = owner.begin() // Its debounce window is replaced before delivery.
        let newestA = owner.begin() // Same input, different submitted intent.
        #expect(throws: CancellationError.self) { try undeliveredB() }
        try newestA()
        effects.append(300)
        suspension.finish(1, value: 100)
        let oldCommitted = await old.value
        #expect(!oldCommitted && effects.values == [300])
    }
}
