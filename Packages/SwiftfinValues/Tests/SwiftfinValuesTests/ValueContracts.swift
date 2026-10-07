//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation
import SwiftfinValues
import Testing

struct ValueContracts {
    private struct Value: Equatable, Sendable { var count = 1
        var label = "original"
    }

    @Test
    func `bounds preserve endpoints and support non numeric comparable values`() {
        #expect(clamp(-10, min: 0, max: 5) == 0)
        #expect(clamp(3, min: 0, max: 5) == 3)
        #expect(clamp(10, min: 0, max: 5) == 5)
        #expect(clamp("b", min: "c", max: "z") == "c")
    }

    @Test
    func `key path copy preserves original and adjacent fields`() {
        let original = Value()
        let changed = copy(original, modifying: \.count, to: 9)
        #expect(original.count == 1 && changed.count == 9)
        #expect(changed.label == original.label)
    }

    @Test
    func `scoped mutation returns the changed value without mutating its input`() {
        let original = Value()
        let changed = with(original) { $0.count = 4
            $0.label = "changed"
        }
        #expect(original == Value())
        #expect(changed.count == 4 && changed.label == "changed")
    }

    @Test
    func `step rounding preserves nearest and away from zero tie behavior`() {
        #expect(round(1.24, toNearest: 0.5) == 1)
        #expect(round(1.25, toNearest: 0.5) == 1.5)
        #expect(round(-1.25, toNearest: 0.5) == -1.5)
        #expect(round(13, toNearest: 5) == 15)
        #expect(round(-13, toNearest: 5) == -15)
    }

    @Test
    func `transformations can run on independent executors`() async {
        let result = await Task.detached { copy(Value(), modifying: \.label, to: "worker") }.value
        #expect(result.count == 1 && result.label == "worker")
    }
}
