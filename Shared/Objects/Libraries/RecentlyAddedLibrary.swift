//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import JellyfinAPI
import SwiftfinLocalization
import SwiftfinMediaCatalog

struct RecentlyAddedLibrary: BaseItemKindLibrary {

    let libraryItemTypes: [BaseItemKind] = [.movie, .series]
    let parent: TitledLibraryParent = .init(displayTitle: L10n.recentlyAdded.localizedCapitalized, id: "recently-added")

    func retrievePage(
        environment: Empty,
        pageState: LibraryPageState
    ) async throws -> [BaseItemDto] {
        try await pageState.readMedia(.recent).items
    }
}
