//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation
import SwiftfinScrolling
import Testing

@Test
func `centering clamps leading middle and trailing positions`() {
    #expect(ScrollCentering.offset(target: -1, viewport: 400, content: 2000) == 0)
    #expect(ScrollCentering.offset(target: 1000, viewport: 400, content: 2000) == 800)
    #expect(ScrollCentering.offset(target: 5000, viewport: 400, content: 2000) == 1600)
}

@Test
func `non scrollable viewport does not issue offset`() {
    #expect(ScrollCentering.offset(target: 10, viewport: 0, content: 20) == nil)
    #expect(ScrollCentering.offset(target: 10, viewport: 20, content: 20) == nil)
    #expect(ScrollCentering.offset(target: 10, viewport: 30, content: 20) == nil)
}

@Test
func `invalid geometry cannot reach native ui`() {
    for (target, viewport, content) in [(CGFloat.nan, 400, 2000), (0, .infinity, 2000), (0, 400, .infinity), (0, 400, .nan)] {
        #expect(ScrollCentering.offset(target: target, viewport: viewport, content: content) == nil)
    }
}

@Test
func `pure geometry executes on worker actor`() async {
    let value = await Task.detached { ScrollCentering.offset(target: 1000, viewport: 400, content: 2000) }.value
    #expect(value == 800)
}
