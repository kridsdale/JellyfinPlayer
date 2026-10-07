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

struct IntegerConversionContracts {
    @Test
    func `optional integer conversion preserves nil and truncates toward zero`() {
        #expect(Int(nil as CGFloat?) == nil)
        #expect(Int(CGFloat(3.9) as CGFloat?) == 3)
        #expect(Int(CGFloat(-3.9) as CGFloat?) == -3)
        #expect(Int(CGFloat(0) as CGFloat?) == 0)
    }
}
