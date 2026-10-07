//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import JellyfinAPI
import SwiftfinMediaCatalog
import Testing

struct GroupedItemQueryContracts {
    @Test
    func `box set group workaround preserves exact parent user and other filter parameters`() {
        let query = CatalogItemQuery(
            parentID: "approved-parent",
            parentType: .folder,
            collectionType: nil,
            filters: .init(itemTypes: MediaCatalogPolicy.groupedItemTypes(for: .boxSet), tags: ["selected-tag"])
        )
        let p = MediaCatalogPolicy.itemParameters(query, userID: "restricted-user", page: .init(offset: 12, limit: 24), mode: .browse)
        #expect(p.includeItemTypes == [.boxSet, .userView])
        #expect(p.parentID == "approved-parent" && p.userID == "restricted-user" && p.tags == ["selected-tag"])
        #expect(p.startIndex == 12 && p.limit == 24 && p.isRecursive == nil)
    }

    @Test
    func `movie episode and existing mixed item filters are never widened`() {
        for kind in [BaseItemKind.movie, .episode, .userView] {
            #expect(MediaCatalogPolicy.groupedItemTypes(for: kind) == [kind])
        }
        let types: [BaseItemKind] = [.boxSet, .movie, .boxSet]
        let p = MediaCatalogPolicy.itemParameters(
            .init(parentID: nil, parentType: nil, collectionType: nil, filters: .init(itemTypes: types)),
            userID: "restricted-user",
            page: .init(offset: 0, limit: 20),
            mode: .browse
        )
        #expect(p.includeItemTypes == types)
    }
}
