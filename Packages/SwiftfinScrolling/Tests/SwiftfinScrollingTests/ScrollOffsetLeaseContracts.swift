//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation
@testable import SwiftfinScrolling
import Testing

@MainActor
private final class ScrollTarget {}
@MainActor
private final class ScrollDriver {
    var receipts: [@MainActor @Sendable (CGFloat) -> Void] = []
    var retired = 0
    func subscribe(_ target: ScrollTarget, _ receive: @escaping @MainActor @Sendable (CGFloat) -> Void) -> @MainActor () -> Void {
        receipts.append(receive)
        return { [weak self] in self?.retired += 1 }
    }
}

@MainActor
private final class WeakScrollLease {
    weak var owner: ScrollOffsetLease<ScrollTarget>?
    init(_ owner: ScrollOffsetLease<ScrollTarget>) {
        self.owner = owner
    }
}

@Suite(.serialized) @MainActor
struct ScrollOffsetLeaseContracts {
    @Test
    func `same target reuses observation and publishes only to latest binding`() {
        let lease = ScrollOffsetLease<ScrollTarget>(), target = ScrollTarget(), driver = ScrollDriver()
        var old: [CGFloat] = [], current: [CGFloat] = []
        lease.connect(target, receive: { old.append($0) }, subscribe: driver.subscribe)
        driver.receipts[0](1)
        lease.connect(target, receive: { current.append($0) }, subscribe: driver.subscribe)
        driver.receipts[0](2)
        #expect(driver.receipts.count == 1 && old == [1] && current == [2])
        lease.disconnect()
        #expect(driver.retired == 1)
    }

    @Test
    func `target replacement rejects old queued callbacks and retires once`() {
        let lease = ScrollOffsetLease<ScrollTarget>(), a = ScrollTarget(), b = ScrollTarget(), driver = ScrollDriver()
        var values: [CGFloat] = []
        lease.connect(a, receive: { values.append($0) }, subscribe: driver.subscribe)
        lease.connect(b, receive: { values.append($0) }, subscribe: driver.subscribe)
        driver.receipts[0](1)
        driver.receipts[1](2)
        #expect(values == [2] && driver.retired == 1)
        lease.disconnect()
        lease.disconnect()
        #expect(driver.retired == 2)
    }

    @Test
    func `disconnect and reconnect same identity revoke old generation`() {
        let lease = ScrollOffsetLease<ScrollTarget>(), target = ScrollTarget(), driver = ScrollDriver()
        var values: [CGFloat] = []
        lease.connect(target, receive: { values.append($0) }, subscribe: driver.subscribe)
        lease.disconnect()
        driver.receipts[0](1)
        lease.connect(target, receive: { values.append($0) }, subscribe: driver.subscribe)
        driver.receipts[0](2)
        driver.receipts[1](3)
        #expect(values == [3] && driver.retired == 1)
        lease.disconnect()
    }

    @Test
    func `reentrant connection retires obsolete subscription without replacing newer owner`() {
        let lease = ScrollOffsetLease<ScrollTarget>(), a = ScrollTarget(), b = ScrollTarget(), driver = ScrollDriver()
        var values: [CGFloat] = []
        lease.connect(a, receive: { values.append($0) }) { target, receive in
            let cleanup = driver.subscribe(target, receive)
            lease.connect(b, receive: { values.append($0) }, subscribe: driver.subscribe)
            return cleanup
        }
        driver.receipts[0](1)
        driver.receipts[1](2)
        #expect(values == [2] && driver.retired == 1)
        lease.disconnect()
        #expect(driver.retired == 2)
    }

    @Test
    func `retained callback neither retains lease nor publishes after release`() throws {
        let target = ScrollTarget(), driver = ScrollDriver()
        var lease: ScrollOffsetLease<ScrollTarget>? = ScrollOffsetLease()
        let weak = try WeakScrollLease(#require(lease))
        var delivered = 0
        lease?.connect(target, receive: { _ in delivered += 1 }, subscribe: driver.subscribe)
        lease = nil
        #expect(weak.owner == nil && driver.retired == 1)
        driver.receipts[0](1)
        #expect(delivered == 0)
    }

    @Test
    func `retirement reentry keeps the newer target and never leaks its token`() {
        let lease = ScrollOffsetLease<ScrollTarget>(), a = ScrollTarget(), b = ScrollTarget(), c = ScrollTarget(), driver = ScrollDriver()
        var values: [CGFloat] = []
        lease.connect(a, receive: { values.append($0) }) { target, receive in
            let cleanup = driver.subscribe(target, receive)
            return {
                cleanup()
                lease.connect(c, receive: { values.append($0) }, subscribe: driver.subscribe)
            }
        }
        lease.connect(b, receive: { values.append($0) }, subscribe: driver.subscribe)
        driver.receipts[0](1)
        driver.receipts[1](3)
        #expect(values == [3] && driver.receipts.count == 2 && driver.retired == 1)
        lease.disconnect()
        #expect(driver.retired == 2)
    }
}
