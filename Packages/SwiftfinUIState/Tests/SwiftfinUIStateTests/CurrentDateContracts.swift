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

@MainActor
private final class SyntheticDateClock {
    var now = Date(timeIntervalSince1970: 100)
}

@MainActor
private final class SyntheticDateScheduler: CurrentDateScheduling {
    var intervals: [TimeInterval] = []
    var callbacks: [@MainActor () -> Void] = []
    var cancellations: [Int] = []
    func subscribe(every interval: TimeInterval, tick: @escaping @MainActor () -> Void) -> AnyCancellable {
        let id = callbacks.count
        intervals.append(interval)
        callbacks.append(tick)
        return AnyCancellable { [weak self] in
            MainActor.preconditionIsolated()
            self?.cancellations.append(id)
        }
    }
}

@MainActor
struct CurrentDateContracts {
    @Test
    func `initial date and writable projection preserve presentation contract`() {
        let clock = SyntheticDateClock(), source = SyntheticDateScheduler()
        let owner = CurrentDateObserver(now: { clock.now }, scheduler: source)
        let wrapper = CurrentDate(observer: owner)
        #expect(wrapper.wrappedValue == clock.now && source.intervals == [1])
        let manual = Date(timeIntervalSince1970: 42)
        wrapper.projectedValue.wrappedValue = manual
        #expect(owner.currentDate == manual && wrapper.wrappedValue == manual)
        clock.now = Date(timeIntervalSince1970: 200)
        source.callbacks[0]()
        #expect(wrapper.wrappedValue == clock.now)
    }

    @Test
    func `requested fractional interval reaches the scheduler`() {
        let source = SyntheticDateScheduler()
        let owner = CurrentDateObserver(interval: 0.25, now: { Date(timeIntervalSince1970: 1) }, scheduler: source)
        #expect(source.intervals == [0.25])
        withExtendedLifetime(owner) {}
    }

    @Test
    func `ticks publish current wall clock synchronously on owner actor`() {
        let clock = SyntheticDateClock(), source = SyntheticDateScheduler()
        let owner = CurrentDateObserver(interval: 5, now: { clock.now }, scheduler: source)
        var received: [Date] = []
        let subscription = owner.$currentDate.dropFirst().sink { value in
            MainActor.preconditionIsolated()
            received.append(value)
        }
        clock.now = Date(timeIntervalSince1970: -10)
        source.callbacks[0]()
        clock.now = Date(timeIntervalSince1970: 1000)
        source.callbacks[0]()
        #expect(received == [Date(timeIntervalSince1970: -10), clock.now])
        #expect(source.intervals == [5])
        withExtendedLifetime(subscription) {}
    }

    @Test
    func `releasing owner cancels even when publisher and late callback survive`() throws {
        let clock = SyntheticDateClock(), source = SyntheticDateScheduler()
        var owner: CurrentDateObserver? = CurrentDateObserver(now: { clock.now }, scheduler: source)
        weak let weakOwner = owner
        var received: [Date] = []
        let subscription = try #require(owner).$currentDate.dropFirst().sink { received.append($0) }
        owner = nil
        #expect(weakOwner == nil && source.cancellations == [0])
        clock.now = Date(timeIntervalSince1970: 200)
        source.callbacks[0]()
        #expect(received.isEmpty && source.cancellations == [0])
        withExtendedLifetime(subscription) {}
    }

    @Test
    func `cancelling A view subscriber does not stop other owner updates`() {
        let clock = SyntheticDateClock(), source = SyntheticDateScheduler()
        let owner = CurrentDateObserver(now: { clock.now }, scheduler: source)
        var received = 0
        let subscription = owner.$currentDate.dropFirst().sink { _ in received += 1 }
        subscription.cancel()
        clock.now = Date(timeIntervalSince1970: 300)
        source.callbacks[0]()
        #expect(received == 0 && owner.currentDate == clock.now && source.cancellations.isEmpty)
    }

    @Test
    func `invalid intervals fall back to one second without busy looping`() {
        for interval in [0, -1, Double.nan, .infinity, -.infinity] {
            let source = SyntheticDateScheduler()
            let owner = CurrentDateObserver(interval: interval, now: { Date(timeIntervalSince1970: 0) }, scheduler: source)
            #expect(source.intervals == [1])
            withExtendedLifetime(owner) {}
        }
    }
}
