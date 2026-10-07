//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import JellyfinAPI
import SwiftfinItemMetadata

struct RemoteImageProvidersLibrary: PagingLibrary {

    let hasNextPage: Bool = false
    let parent: TitledLibraryParent

    init(itemID: String) {
        self.parent = .init(displayTitle: "Providers", id: itemID)
    }

    func retrievePage(
        environment: Empty,
        pageState: LibraryPageState
    ) async throws -> [ImageProviderInfo] {
        guard pageState.pageOffset == 0, let itemID = parent.id else { return [] }
        return try await pageState.itemMetadata.imageProviders(itemID: itemID)
    }
}
