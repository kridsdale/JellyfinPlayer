//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import SwiftfinAccountAccess
import Testing

struct LocalAccessPolicyContracts {
    @Test
    func `pin length boundaries retain the installed rule`() {
        for count in 0 ... 33 {
            #expect(LocalAccessPINPolicy.isValid(String(repeating: "0", count: count)) == (count >= 4 && count <= 30))
        }
    }

    @Test
    func `unicode pins count graphemes and remain nonnumeric`() {
        #expect(LocalAccessPINPolicy.isValid("👨‍👩‍👧‍👦á🦄字"))
        #expect(!LocalAccessPINPolicy.isValid("👨‍👩‍👧‍👦á🦄"))
        #expect(LocalAccessPINPolicy.isValid("    "))
        #expect(LocalAccessPINPolicy.isValid(String(repeating: "á", count: 30)))
        #expect(!LocalAccessPINPolicy.isValid(String(repeating: "á", count: 31)))
    }

    @Test
    func `prompt result preserves exact bytes and optional hint`() {
        let pin = " 0á🦄 "
        let value: any EvaluatedLocalUserAccessPolicy = PinEvaluatedUserAccessPolicy(pin: pin, pinHint: nil)
        let result = value as? PinEvaluatedUserAccessPolicy
        #expect(result?.pin.utf8.elementsEqual(pin.utf8) == true && result?.pinHint == nil)
        #expect(PinEvaluatedUserAccessPolicy(pin: "0000", pinHint: "").pinHint == "")
    }

    @Test
    func `immutable prompt result transfers without actor or storage ownership`() async {
        let value = PinEvaluatedUserAccessPolicy(pin: "synthetic", pinHint: "hint")
        let result = await Task.detached { () -> PinEvaluatedUserAccessPolicy in value }.value
        #expect(result.pin == "synthetic" && result.pinHint == "hint")
    }
}
