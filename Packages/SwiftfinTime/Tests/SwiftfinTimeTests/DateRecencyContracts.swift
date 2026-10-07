//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation
import SwiftfinTime
import Testing

struct DateRecencyContracts {
    @Test
    func `recency is strict at the exact interval boundary`() {
        let start = Date(timeIntervalSince1970: 1000)
        #expect(start.isRecent(with: .seconds(180), comparedTo: start.addingTimeInterval(179.999)))
        #expect(!start.isRecent(with: .seconds(180), comparedTo: start.addingTimeInterval(180)))
        #expect(!start.isStale(with: .seconds(180), comparedTo: start.addingTimeInterval(180)))
        #expect(start.isStale(with: .seconds(180), comparedTo: start.addingTimeInterval(180.001)))
    }

    @Test
    func `future dates and clock rollback retain original recency`() {
        let now = Date(timeIntervalSince1970: 1000)
        #expect(now.addingTimeInterval(1).isRecent(with: .seconds(180), comparedTo: now))
        #expect(!Date.distantPast.isRecent(with: .seconds(180), comparedTo: now))
        #expect(now.isRecent(with: .seconds(180), comparedTo: now))
    }

    @Test
    func `zero and negative windows retain raw strict comparison`() {
        let now = Date(timeIntervalSince1970: 1000)
        #expect(!now.isRecent(with: .zero, comparedTo: now))
        #expect(now.addingTimeInterval(1).isRecent(with: .zero, comparedTo: now))
        #expect(!now.isRecent(with: .seconds(-1), comparedTo: now))
    }
}
