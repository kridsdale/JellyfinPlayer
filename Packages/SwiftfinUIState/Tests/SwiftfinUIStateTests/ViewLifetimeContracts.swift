//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation
import os
import SwiftfinUIState
import Testing

@MainActor
private final class EndReceipt {
    var count = 0
    var isEmpty: Bool {
        count == 0
    }

    func end() {
        MainActor.preconditionIsolated()
        count += 1
    }
}

@MainActor
private final class WeakLifetime {
    weak var owner: ViewLifetimeObserver?
    init(_ owner: ViewLifetimeObserver) {
        self.owner = owner
    }
}

private struct ReleaseSlot: Sendable {
    private let state: OSAllocatedUnfairLock<ViewLifetimeObserver?>
    init(_ owner: ViewLifetimeObserver) {
        state = .init(initialState: owner)
    }

    func drop() {
        let owner = state.withLock { value in let owner = value
            value = nil
            return owner
        }
        withExtendedLifetime(owner) {}
    }
}

@Suite(.serialized) @MainActor
struct ViewLifetimeContracts {
    private func boxed(_ receipt: EndReceipt) -> (ReleaseSlot, WeakLifetime) {
        let owner = ViewLifetimeObserver { receipt.end() }
        return (ReleaseSlot(owner), WeakLifetime(owner))
    }

    @Test
    func `last UI actor release delivers exactly once without early delivery`() throws {
        let receipt = EndReceipt()
        var owner: ViewLifetimeObserver? = ViewLifetimeObserver { receipt.end() }
        let weak = try WeakLifetime(#require(owner))
        #expect(receipt.isEmpty && weak.owner != nil)
        owner = nil
        #expect(receipt.count == 1 && weak.owner == nil)
    }

    @Test
    func `foreign last release delivers on the UI actor and retires its owner`() async {
        let receipt = EndReceipt()
        let (slot, weak) = boxed(receipt)
        #expect(receipt.isEmpty)
        await Task.detached { slot.drop() }.value
        for _ in 0 ..< 10000 where receipt.isEmpty {
            await Task.yield()
        }
        #expect(receipt.count == 1 && weak.owner == nil)
        await Task.detached { slot.drop() }.value
        #expect(receipt.count == 1)
    }

    @Test
    func `independent view lifetimes never retire each other`() {
        let first = EndReceipt(), second = EndReceipt()
        let (a, weakA) = boxed(first), (b, weakB) = boxed(second)
        a.drop()
        #expect(first.count == 1 && second.isEmpty && weakA.owner == nil && weakB.owner != nil)
        b.drop()
        #expect(second.count == 1 && weakB.owner == nil)
    }
}
