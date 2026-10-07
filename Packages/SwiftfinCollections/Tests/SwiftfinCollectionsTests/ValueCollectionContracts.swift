//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation
import OrderedCollections
import SwiftfinCollections
import Testing

private struct Flags: OptionSet, Sendable {
    let rawValue: Int
    static let first = Flags(rawValue: 1)
    static let second = Flags(rawValue: 2)
}

@Suite("Generic collection value ownership")
struct ValueCollectionContracts {
    @Test
    func `dictionary projections preserve adjacent keys input and optional lookup`() {
        let original = ["first": 1, "second": 2]
        let changed = original.inserting(value: 9, for: "first").removingValue(for: "second")
        let nilKey: String? = nil, key: String? = "first", missing: String? = "absent"
        #expect(changed == ["first": 9] && original == ["first": 1, "second": 2])
        #expect(original[nilKey] == nil && original[key] == 1 && original[missing] == nil)
    }

    @Test
    func `shared set algebra preserves concrete sets and option sets`() {
        var set: Set<Int> = [1]
        set.toggle(value: 1)
        set.toggle(value: 2)
        set.insert(contentsOf: [2, 3, 3])
        #expect(set == [2, 3])
        #expect(set.inserting(4, if: false) == set && set.removing(2, if: false) == set)
        #expect(set.inserting(4).removing(2) == [3, 4] && set == [2, 3])
        #expect(set.inserting(4, if: true).removing(2, if: true) == [3, 4])
        var flags: Flags = [.first]
        flags.toggle(value: .first)
        flags.insert(contentsOf: [.second, .second])
        #expect(flags == .second)
        #expect(flags.inserting(.first).removing(.second) == .first && flags == .second)
    }

    @Test
    func `ordered dictionary projections retain value order and filter nil keys only`() {
        let optional: OrderedDictionary<String?, Int> = ["ccc": 3, nil: 0, "a": 1, "bb": 2]
        let compact = optional.compactKeys()
        #expect(Array(compact.keys) == ["ccc", "a", "bb"] && Array(compact.values) == [3, 1, 2])
        #expect(Array(compact.sortedKeys(by: <).keys) == ["a", "bb", "ccc"])
        #expect(Array(compact.sortedKeys(using: { $0.count }).keys) == ["a", "bb", "ccc"])
        #expect(optional.count == 4 && optional.isNotEmpty && !OrderedDictionary<String, Int>().isNotEmpty)
    }

    @Test
    func `optional append returns a projection without assigning the optional`() {
        var missing: [Int]? = nil, existing: [Int]? = [1, 2]
        #expect(missing.isNilOrEmpty && !existing.isNilOrEmpty)
        let initialized = missing.appendedOrInit(3), appended = existing.appendedOrInit(3)
        #expect(initialized == [3] && missing == nil)
        #expect(appended == [1, 2, 3] && existing == [1, 2])
        let empty: String? = "", text: String? = "x"
        #expect(empty.isNilOrEmpty && !text.isNilOrEmpty)
    }

    @Test
    func `collection projections transfer immutable inputs across executors`() async {
        let ordered: OrderedDictionary<String, Int> = ["b": 2, "a": 1]
        let result = await Task.detached {
            (ordered.sortedKeys(by: <), ["a": 1].inserting(value: 2, for: "b"), Set([1]).inserting(2))
        }.value
        #expect(Array(result.0.keys) == ["a", "b"] && result.1 == ["a": 1, "b": 2] && result.2 == [1, 2])
    }
}
