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

private actor JumpClock {
    private var pending: [(Duration, CheckedContinuation<Void, any Error>?)] = []
    var count: Int {
        pending.count
    }

    var delays: [Duration] {
        pending.map(\.0)
    }

    func wait(_ delay: Duration) async throws {
        try await withCheckedThrowingContinuation { pending.append((delay, $0)) }
    }

    func release(_ index: Int) {
        let c = pending[index].1
        pending[index].1 = nil
        c?.resume()
    }
}

@MainActor
private final class WeakJump {
    weak var owner: JumpProgressObserver?
    init(_ owner: JumpProgressObserver) {
        self.owner = owner
    }
}

@Suite(.serialized) @MainActor
struct JumpProgressContracts {
    private enum Failure: Error { case timeout }
    private func wait(_ clock: JumpClock, count: Int) async throws {
        for _ in 0 ..< 10000 {
            if await clock.count >= count {
                return
            }
            await Task.yield()
        }
        throw Failure.timeout
    }

    private func settle() async {
        for _ in 0 ..< 100 {
            await Task.yield()
        }
    }

    @Test
    func `all independently captured original direction and reset traces remain exact`() {
        let originals: [(String, [Int])] = [
            ("", [0]),
            ("FFF", [0, 1, 2, 3]),
            ("BBB", [0, 1, 2, 3]),
            ("FFBBF", [0, 1, 2, 1, 2, 1]),
            ("BBFFB", [0, 1, 2, 1, 2, 1]),
            ("FRFB", [0, 1, 0, 1, 1]),
            ("BBRBF", [0, 1, 2, 0, 1, 1]),
            ("FBFB", [0, 1, 1, 1, 1])
        ]
        for (operations, expected) in originals {
            let owner = JumpProgressObserver()
            var counts = [owner.jumps]
            for operation in operations {
                switch operation { case "F": owner.jumpForward()
                case "B": owner.jumpBackward()
                default: owner.reset() }
                counts.append(owner.jumps)
            }
            owner.timer.stop()
            #expect(counts == expected)
        }
    }

    @Test
    func `replacement expiry resets current count and preserves explicit intervals`() async throws {
        let clock = JumpClock()
        let timer = PokeIntervalTimer(defaultInterval: 2, sleep: { try await clock.wait($0) })
        let owner = JumpProgressObserver(interval: 2, timer: timer)
        owner.jumpForward()
        try await wait(clock, count: 1)
        owner.jumpForward(interval: 0.35)
        try await wait(clock, count: 2)
        #expect(owner.jumps == 2)
        await clock.release(0)
        await settle()
        #expect(owner.jumps == 2)
        await clock.release(1)
        await settle()
        #expect(owner.jumps == 0)
        #expect(await clock.delays == [.seconds(2), .seconds(0.35)])
    }

    @Test
    func `external timer does not retain released jump owner`() async throws {
        let clock = JumpClock()
        let timer = PokeIntervalTimer(defaultInterval: 2, sleep: { try await clock.wait($0) })
        var owner: JumpProgressObserver? = JumpProgressObserver(interval: 2, timer: timer)
        let weak = try WeakJump(#require(owner))
        owner?.jumpBackward()
        try await wait(clock, count: 1)
        owner = nil
        #expect(weak.owner == nil)
        await clock.release(0)
        await settle()
        #expect(weak.owner == nil)
    }

    @Test
    func `manual reset preserves the same deadline owner and does not cancel expiry`() async throws {
        let clock = JumpClock()
        let timer = PokeIntervalTimer(defaultInterval: 2, sleep: { try await clock.wait($0) })
        let owner = JumpProgressObserver(interval: 2, timer: timer)
        var expiry = 0
        let subscription = timer.sink { expiry += 1 }
        owner.jumpBackward()
        try await wait(clock, count: 1)
        owner.reset()
        #expect(owner.jumps == 0 && owner.timer === timer)
        await clock.release(0)
        await settle()
        #expect(expiry == 1 && owner.jumps == 0)
        subscription.cancel()
    }
}
