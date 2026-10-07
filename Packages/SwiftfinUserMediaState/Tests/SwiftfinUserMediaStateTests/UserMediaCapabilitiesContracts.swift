//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import JellyfinAPI
import SwiftfinUserMediaState
import Testing

struct UserMediaCapabilitiesContracts {
    @Test
    func `program watched state excludes live kinds while favorites permit unknown types`() {
        for kind in [BaseItemKind.program, .liveTvProgram, .tvProgram] {
            let capabilities = UserMediaStatePolicy.capabilities(for: kind)
            #expect(!capabilities.canBeFavorited && !capabilities.canBePlayed)
        }
        #expect(UserMediaStatePolicy.capabilities(for: nil).canBeFavorited)
        #expect(!UserMediaStatePolicy.capabilities(for: nil).canBePlayed)
    }

    @Test
    func `series watched state is available while channel watched state is absent`() {
        #expect(UserMediaStatePolicy.capabilities(for: .series).canBePlayed)
        #expect(UserMediaStatePolicy.capabilities(for: .episode).canBePlayed)
        #expect(!UserMediaStatePolicy.capabilities(for: .channel).canBePlayed)
        #expect(UserMediaStatePolicy.capabilities(for: .channel).canBeFavorited)
    }
}
