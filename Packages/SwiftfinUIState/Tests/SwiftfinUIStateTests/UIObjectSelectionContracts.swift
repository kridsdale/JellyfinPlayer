//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

// Swiftfin is subject to the Mozilla Public License, v2.0.
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
import Combine
import SwiftfinUIState
import Testing

@Suite(.serialized) @MainActor
struct UIObjectSelectionContracts {
    private final class Item: Equatable {
        let label: String
        init(_ label: String) {
            self.label = label
        }

        nonisolated static func == (lhs: Item, rhs: Item) -> Bool {
            lhs.label == rhs.label
        }
    }

    @Test
    func `retirement uses object identity and cannot clear A newer selection`() {
        let state = UIObjectSelection<Item>()
        let a = Item("same")
        let b = Item("same")
        #expect(a == b)
        state.apply(.activated(a))
        state.apply(.activated(b))
        state.apply(.retired(a))
        #expect(state.current === b)
        state.apply(.retired(b))
        #expect(state.current == nil)
        state.apply(.retired(a))
        #expect(state.current == nil)
    }

    @Test
    func `publisher delivery is immediate and cancellation stops changes`() {
        let events = UIEventPublisher<UIObjectEvent<Item>>()
        let state = UIObjectSelection<Item>()
        let a = Item("a")
        let b = Item("b")
        let subscription = events.sink { state.apply($0) }
        events.send(.activated(a))
        #expect(state.current === a)
        events.send(.activated(b))
        events.send(.retired(a))
        #expect(state.current === b)
        subscription.cancel()
        events.send(.retired(b))
        #expect(state.current === b)
        state.clear()
        #expect(state.current == nil)
    }

    @Test
    func `account clear and old retirement do not retain previous objects`() throws {
        let state = UIObjectSelection<Item>()
        var a: Item? = Item("old")
        weak let weakA = a
        try state.apply(.activated(#require(a)))
        a = nil
        #expect(weakA != nil)
        state.clear()
        #expect(weakA == nil)
        let b = Item("new")
        state.apply(.activated(b))
        state.apply(.retired(Item("old")))
        #expect(state.current === b)
    }

    @Test
    func `replacing selection releases the old object and same object can reopen`() throws {
        let state = UIObjectSelection<Item>()
        var a: Item? = Item("old")
        weak let weakA = a
        try state.apply(.activated(#require(a)))
        a = nil
        let b = Item("new")
        state.apply(.activated(b))
        #expect(weakA == nil)
        state.apply(.retired(b))
        state.apply(.activated(b))
        #expect(state.current === b)
    }
}
