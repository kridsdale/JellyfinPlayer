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

@Suite("Wall-clock cache staleness")
struct DateStalenessContracts {
    @Test
    func `staleness boundary is strict and retains signed fractional duration behavior`() {
        let origin = Date(timeIntervalSince1970: 0)
        #expect(!origin.isStale(with: .seconds(0.5), comparedTo: origin.addingTimeInterval(0.5)))
        #expect(origin.isStale(with: .seconds(0.5), comparedTo: origin.addingTimeInterval(0.5001)))
        #expect(!origin.isStale(with: .zero, comparedTo: origin))
        #expect(!origin.addingTimeInterval(1).isStale(with: .zero, comparedTo: origin))
        #expect(origin.isStale(with: .seconds(-1), comparedTo: origin))
    }

    @Test
    func `existing one-argument call still uses current wall time independently of UI actor`() async {
        let past = Date.now.addingTimeInterval(-120), future = Date.now.addingTimeInterval(120)
        let result = await Task.detached { (past.isStale(with: .minutes(1)), future.isStale(with: .zero)) }.value
        #expect(result.0 && !result.1)
    }
}
