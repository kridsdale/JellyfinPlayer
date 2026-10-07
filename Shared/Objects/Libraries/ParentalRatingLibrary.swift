//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import JellyfinAPI
import SwiftfinItemMetadata

struct ParentalRatingLibrary: PagingLibrary {

    let hasNextPage: Bool = false
    let parent: TitledLibraryParent = .init(displayTitle: "", id: "parental-ratings")

    func retrievePage(
        environment: Empty,
        pageState: LibraryPageState
    ) async throws -> [ParentalRating] {
        guard pageState.pageOffset == 0 else { return [] }
        return try await pageState.itemMetadata.parentalRatings()
    }
}
