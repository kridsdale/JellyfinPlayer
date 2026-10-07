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

private struct Record: Equatable, Sendable { var value: Int
    var adjacent: String
}

@Suite("Comparable and key-path value projections")
struct ProjectionContracts {
    @Test
    func `generic clamping retains strict bounds for numeric and string values`() {
        #expect((-1).clamped(to: 0 ... 10) == 0 && 11.clamped(to: 0 ... 10) == 10 && 5.clamped(to: 0 ... 10) == 5)
        #expect("a".clamped(to: "b" ... "m") == "b" && "z".clamped(to: "b" ... "m") == "m")
        #expect(0.25.clamped(to: 0 ... 1) == 0.25)
    }

    @Test
    func `key-path mutation returns an independent struct with adjacent data preserved`() async {
        let original = Record(value: 1, adjacent: "keep")
        let changed = await Task.detached { original.mutating(\.value, with: 9) }.value
        #expect(changed == Record(value: 9, adjacent: "keep") && original == Record(value: 1, adjacent: "keep"))
    }
}
