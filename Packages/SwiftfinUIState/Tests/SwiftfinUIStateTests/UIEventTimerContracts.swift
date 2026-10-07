//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Combine
import Foundation
@testable import SwiftfinUIState
import Testing

private actor DeadlineGate {
    private var deadlines: [(Duration, CheckedContinuation<Void, any Error>?)] = []
    var count: Int {
        deadlines.count
    }

    var durations: [Duration] {
        deadlines.map(\.0)
    }

    func suspend(_ duration: Duration) async throws {
        try await withCheckedThrowingContinuation { continuation in
            deadlines.append((duration, continuation))
        }
    }

    func release(_ index: Int) {
        let continuation = deadlines[index].1
        deadlines[index].1 = nil
        continuation?.resume()
    }
}

@Suite(.serialized) @MainActor
struct UIEventTimerContracts {
    private final class UIValue { let id: Int
        init(_ id: Int) {
            self.id = id
        }
    }

    @Test
    func `event copies deliver synchronously on the UI actor without replaying`() {
        let publisher = UIEventPublisher<UIValue>()
        let copy = publisher
        var first: [Int] = []
        var second: [Int] = []
        let a = publisher.sink { value in MainActor.preconditionIsolated()
            first.append(value.id)
        }
        copy.send(UIValue(1))
        let b = copy.sink { value in MainActor.preconditionIsolated()
            second.append(value.id)
        }
        publisher.send(UIValue(2))
        #expect(first == [1, 2] && second == [2])
        a.cancel()
        copy.send(UIValue(3))
        #expect(first == [1, 2] && second == [2, 3])
        b.cancel()
    }

    @Test
    func `event delivery supports reentry and does not retain its payload`() throws {
        let publisher = UIEventPublisher<UIValue>()
        var values: [Int] = []
        let observation = publisher.sink { value in
            values.append(value.id)
            if value.id == 1 {
                publisher.send(UIValue(2))
            }
        }
        var value: UIValue? = UIValue(1)
        weak let weakValue = value
        try publisher.send(#require(value))
        value = nil
        #expect(values == [1, 2])
        #expect(weakValue == nil)
        withExtendedLifetime(observation) {}
    }

    private func waitForDeadline(_ count: Int, gate: DeadlineGate) async throws {
        for _ in 0 ..< 10000 {
            if await gate.count >= count {
                return
            }
            await Task.yield()
        }
        throw GateFailure.timeout
    }

    private enum GateFailure: Error { case timeout }
    private func settle() async {
        for _ in 0 ..< 50 {
            await Task.yield()
        }
    }

    @Test
    func `replacing deadline suppresses an already suspended old task`() async throws {
        let gate = DeadlineGate()
        let timer = PokeIntervalTimer(defaultInterval: 5, sleep: { try await gate.suspend($0) })
        var values = 0
        let observation = timer.sink { MainActor.preconditionIsolated()
            values += 1
        }
        timer.poke()
        try await waitForDeadline(1, gate: gate)
        timer.poke(interval: 2)
        try await waitForDeadline(2, gate: gate)
        await gate.release(0)
        await settle()
        #expect(values == 0)
        await gate.release(1)
        await settle()
        #expect(values == 1)
        #expect(await gate.durations == [.seconds(5), .seconds(2)])
        withExtendedLifetime(observation) {}
    }

    @Test
    func `stop rearm and subscriber cancellation keep delivery on the owner`() async throws {
        let gate = DeadlineGate()
        let timer = PokeIntervalTimer(defaultInterval: 1, sleep: { try await gate.suspend($0) })
        var values = 0
        let observation = timer.sink { MainActor.preconditionIsolated()
            values += 1
        }
        timer.poke()
        try await waitForDeadline(1, gate: gate)
        timer.stop()
        await gate.release(0)
        await settle()
        #expect(values == 0)
        timer.poke(interval: 0)
        try await waitForDeadline(2, gate: gate)
        await gate.release(1)
        await settle()
        #expect(values == 1)
        observation.cancel()
        timer.poke()
        try await waitForDeadline(3, gate: gate)
        await gate.release(2)
        await settle()
        #expect(values == 1)
    }

    @Test
    func `releasing timer owner cancels even when its subscriber survives`() async throws {
        let gate = DeadlineGate()
        var timer: PokeIntervalTimer? = PokeIntervalTimer(defaultInterval: 60, sleep: { try await gate.suspend($0) })
        weak let weakTimer = timer
        var delivered = false
        let observation = try #require(timer).sink { delivered = true }
        timer?.poke()
        try await waitForDeadline(1, gate: gate)
        timer = nil
        #expect(weakTimer == nil)
        await gate.release(0)
        await settle()
        #expect(!delivered)
        withExtendedLifetime(observation) {}
    }

    @Test
    func `nonfinite and negative intervals use finite nonnegative deadlines`() async throws {
        let gate = DeadlineGate()
        let timer = PokeIntervalTimer(defaultInterval: .nan, sleep: { try await gate.suspend($0) })
        for (index, value) in [Double(-1), .infinity, .nan, 2].enumerated() {
            timer.poke(interval: value)
            try await waitForDeadline(index + 1, gate: gate)
        }
        #expect(await gate.durations == [.zero, .seconds(5), .seconds(5), .seconds(2)])
        timer.stop()
        for index in 0 ..< 4 {
            await gate.release(index)
        }
        await settle()
    }
}
