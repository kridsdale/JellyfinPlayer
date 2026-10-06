//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Combine
import Foundation

enum TimerTestFailure: Error {
    case expectation(String)
}

@main
struct PokeIntervalTimerTests {
    @MainActor
    static func expect(_ condition: Bool, _ message: String) throws {
        guard condition else { throw TimerTestFailure.expectation(message) }
    }

    @MainActor
    static func main() async throws {
        let timer = PokeIntervalTimer(defaultInterval: 0.15)
        var delivered = 0
        let subscription = timer.sink {
            MainActor.preconditionIsolated()
            delivered += 1
        }
        timer.poke()
        try await Task.sleep(for: .milliseconds(50))
        timer.poke()
        try await Task.sleep(for: .milliseconds(120))
        try expect(delivered == 0, "A newer poke must cancel the original deadline")
        try await Task.sleep(for: .milliseconds(100))
        try expect(delivered == 1, "Only the newest deadline may deliver")

        timer.poke(interval: 0.1)
        timer.stop()
        try await Task.sleep(for: .milliseconds(150))
        try expect(delivered == 1, "Stop must suppress pending delivery")
        timer.poke(interval: 0.02)
        try await Task.sleep(for: .milliseconds(100))
        try expect(delivered == 2, "Stopped timer must be reusable")

        var owner: PokeIntervalTimer? = PokeIntervalTimer(defaultInterval: 60)
        weak let weakOwner = owner
        var orphanDelivery = false
        let retainedSubscription = owner!.sink { orphanDelivery = true }
        owner!.poke()
        owner = nil
        try expect(weakOwner == nil, "A pending timer must not retain its owner")
        try await Task.sleep(for: .milliseconds(50))
        try expect(!orphanDelivery, "Owner release must cancel delivery even with a retained subscriber")
        retainedSubscription.cancel()

        subscription.cancel()
        timer.poke(interval: 0)
        try await Task.sleep(for: .milliseconds(50))
        try expect(delivered == 2, "Cancelled subscription must receive no more events")
        print("PASS: replace deadline, stop, rearm, actor delivery, owner release, subscriber cancellation")
    }
}
