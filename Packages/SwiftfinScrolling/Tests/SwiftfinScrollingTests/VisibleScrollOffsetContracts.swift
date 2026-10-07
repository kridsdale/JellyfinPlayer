//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Combine
import Foundation
import SwiftfinScrolling
import Testing

@Suite(.serialized) @MainActor
struct VisibleScrollOffsetContracts {
    private struct Trace: Decodable { let inputs: [String]
        let states: [String]
        let receipts: [String]
    }

    private let original = #"""
    {
      "inputs": [
        "0000000000000000",
        "3fd0000000000000",
        "3fe0000000000000",
        "3fe000d1b71758e2",
        "3fe999999999999a",
        "3ff0000000000000",
        "3ff000d1b71758e2",
        "bfe0000000000000",
        "bff0000000000000",
        "bff80068db8bac71",
        "7ff0000000000000",
        "7ff0000000000000",
        "7ff8000000000000",
        "0000000000000000",
        "fff0000000000000",
        "0000000000000000"
      ],
      "receipts": [
        "0000000000000000",
        "3fe000d1b71758e2",
        "3ff000d1b71758e2",
        "bfe0000000000000",
        "bff80068db8bac71",
        "7ff0000000000000",
        "0000000000000000",
        "fff0000000000000",
        "0000000000000000"
      ],
      "states": [
        "0000000000000000",
        "0000000000000000",
        "0000000000000000",
        "3fe000d1b71758e2",
        "3fe000d1b71758e2",
        "3fe000d1b71758e2",
        "3ff000d1b71758e2",
        "bfe0000000000000",
        "bfe0000000000000",
        "bff80068db8bac71",
        "7ff0000000000000",
        "7ff0000000000000",
        "7ff0000000000000",
        "0000000000000000",
        "fff0000000000000",
        "0000000000000000"
      ]
    }
    """#
    private func bits(_ value: CGFloat) -> String {
        String(format: "%016llx", Double(value).bitPattern)
    }

    @Test
    func `original threshold signed nonfinite state and synchronous receipts stay exact`() throws {
        let trace = try JSONDecoder().decode(Trace.self, from: Data(original.utf8))
        let state = VisibleScrollOffsetState()
        var receipts: [String] = [], states: [String] = []
        let token = state.visibleLeadingOffsetPublisher.sink { MainActor.preconditionIsolated()
            receipts.append(bits($0))
        }
        for input in trace.inputs {
            let pattern = try #require(UInt64(input, radix: 16))
            state.update(visibleLeadingOffset: CGFloat(Double(bitPattern: pattern)))
            states.append(bits(state.visibleLeadingOffset))
        }
        #expect(states == trace.states && receipts == trace.receipts)
        token.cancel()
    }

    @Test
    func `cancelled receipt stops and a fresh subscriber sees current state immediately`() {
        let state = VisibleScrollOffsetState()
        var old: [CGFloat] = [], current: [CGFloat] = []
        let token = state.visibleLeadingOffsetPublisher.sink { old.append($0) }
        state.update(visibleLeadingOffset: 1)
        token.cancel()
        state.update(visibleLeadingOffset: 2)
        let next = state.visibleLeadingOffsetPublisher.sink { current.append($0) }
        #expect(old == [0, 1] && current == [2])
        state.update(visibleLeadingOffset: 3)
        #expect(current == [2, 3])
        next.cancel()
    }

    @Test
    func `foreign task updates only through the owner and callback stays on the UI actor`() async {
        let state = VisibleScrollOffsetState()
        var values: [CGFloat] = []
        let token = state.visibleLeadingOffsetPublisher.sink { MainActor.preconditionIsolated()
            values.append($0)
        }
        await Task.detached { await state.update(visibleLeadingOffset: 2) }.value
        #expect(values == [0, 2])
        token.cancel()
    }
}
