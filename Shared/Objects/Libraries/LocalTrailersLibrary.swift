//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import JellyfinAPI
import SwiftfinMediaCatalog

struct LocalTrailerLibrary: BaseItemKindLibrary {

    let hasNextPage: Bool = false
    let libraryItemTypes: [BaseItemKind] = [.trailer]
    let parent: TitledLibraryParent

    init(parentID: String) {
        self.parent = .init(displayTitle: "", id: parentID)
    }

    func retrievePage(
        environment: Empty,
        pageState: LibraryPageState
    ) async throws -> [BaseItemDto] {
        guard let itemID = parent.id else { return [] }
        return try await pageState.readMedia(.localTrailers(itemID: itemID)).items
    }
}
