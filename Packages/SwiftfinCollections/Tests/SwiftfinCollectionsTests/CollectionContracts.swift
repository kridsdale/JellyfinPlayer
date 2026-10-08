//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation
import SwiftfinCollections
import Testing

private enum RawLabel: String { case first, second }
@ArrayBuilder<String>
private func labels(optional: String?, enabled: Bool) -> [String] {
    "start"
    optional
    if enabled {
        RawLabel.first
    } else {
        RawLabel.second
    }
    for label in ["one", "two"] {
        label
    }
    [RawLabel.first, RawLabel.second]
    ()
}

@Test
func `builder preserves optional conditional loop raw value and void semantics`() {
    #expect(labels(optional: "present", enabled: true) == ["start", "present", "first", "one", "two", "first", "second"])
    #expect(labels(optional: nil, enabled: false) == ["start", "second", "one", "two", "first", "second"])
}

@Test
func `safe collection access honors slice indices and empty mutation`() {
    let slice = [10, 20, 30, 40][2...]
    #expect(slice[safe: 2] == 30 && slice[safe: 0] == nil && slice[safe: 4] == nil)
    var values = [Int]()
    #expect(values.removeFirstSafe() == nil)
    values = [1, 2]
    #expect(values.removeFirstSafe() == 1 && values == [2])
}

@Test
func `nil sort keys remain last and equal nil elements preserve their order`() {
    struct Row { let id: Int
        let rank: Int?
    }
    let values = [Row(id: 0, rank: nil), Row(id: 1, rank: 2), Row(id: 2, rank: nil), Row(id: 3, rank: 1)]
    #expect(values.sorted(using: \.rank).map(\.id) == [3, 1, 0, 2])
    #expect([Row(id: 1, rank: nil), Row(id: 2, rank: nil)].sorted(using: \.rank).map(\.id) == [1, 2])
}

@Test
func `collection projections coalesce only missing values and preserve set operation order`() {
    struct Row { let id: Int
        var label: String?
    }
    let rows = [Row(id: 1, label: "one"), Row(id: 2, label: nil), Row(id: 3, label: "three")]
    #expect(rows.coalesced(property: \.label, with: "missing").map(\.label) == ["one", "missing", "three"])
    #expect(rows.compacted(using: \.label).map(\.id) == [1, 3])
    #expect(rows.intersecting([3, 1], using: \.id).map(\.id) == [1, 3])
    #expect(rows.subtracting([2], using: \.id).map(\.id) == [1, 3])
    #expect(rows.keyed(using: \.id)[3]?.label == "three")
    #expect([[1, 2], [3]].flattened() == [1, 2, 3])
}

@Test
func `array toggles removals and conditional appends retain original ordering`() {
    var values = [1, 2, 2]
    values.toggle(2)
    #expect(values == [1])
    values.toggle(3)
    #expect(values == [1, 3])
    #expect(values.prepending(0).appending(4) == [0, 1, 3, 4])
    #expect(values.appending(5, if: false) == values)
}
