//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation
import SwiftfinAccountModels
import Testing

struct DeepLinkContracts {
    @Test
    func `supported schemes and legacy library spelling preserve exact identity`() throws {
        for scheme in ["swiftfin", "jellyfin"] {
            for kind in ["item", "library"] {
                for suffix in ["", "/"] {
                    let url = try #require(URL(string: "\(scheme)://Server-01/User-02/\(kind)/Item-03\(suffix)"))
                    let link = try #require(AccountDeepLink(url))
                    #expect(link.serverID == "Server-01" && link.userID == "User-02")
                    #expect(link.destination == .item(id: "Item-03"))
                }
            }
        }
    }

    @Test
    func `malformed or extended UR ls are rejected instead of broadening the route`() throws {
        for text in [
            "https://s/u/item/i",
            "SWIFTFIN://s/u/item/i",
            "swiftfin://s/u/movie/i",
            "swiftfin://s/u/item/i/extra",
            "swiftfin://s/u/item/i?token=private",
            "swiftfin://s/u/item/i#fragment",
            "swiftfin://s:8096/u/item/i",
            "swiftfin://name@s/u/item/i",
            "swiftfin://s//item/i",
            "swiftfin://s/u/item/",
            "swiftfin://s/u/item/i_name",
            "swiftfin://s/u/item/a%20b",
            "swiftfin://s/u/item/a.b"
        ] {
            #expect(try AccountDeepLink(#require(URL(string: text))) == nil)
        }
    }

    @Test
    func `parsed account identity transfers without navigation or session objects`() async throws {
        let url = try #require(URL(string: "jellyfin://server/user/item/movie"))
        let link = try #require(AccountDeepLink(url))
        #expect(await Task.detached { link }.value == link)
    }
}
