//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Defaults
import JellyfinAPI
import SwiftfinLocalization
import SwiftfinMediaCatalog

struct EpisodeLibrary: BaseItemKindLibrary {

    let hasNextPage = false
    let libraryItemTypes: [BaseItemKind] = [.episode]
    let parent: BaseItemDto

    init(season: BaseItemDto) {
        self.parent = season
    }

    func retrievePage(
        environment: Empty,
        pageState: LibraryPageState
    ) async throws -> [BaseItemDto] {
        guard let seasonID = parent.id else { throw ErrorMessage(L10n.unknownError) }
        return try await pageState.readMedia(.episodes(seasonID: seasonID, showMissing: Defaults[.Customization.shouldShowMissingEpisodes]))
            .items
    }
}
