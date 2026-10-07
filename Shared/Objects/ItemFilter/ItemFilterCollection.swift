//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import JellyfinAPI
import SwiftfinCollections
import SwiftfinFilters
import SwiftfinStoredValues

extension ItemFilterCollection: @retroactive Storable {}

extension ItemFilterCollection {
    /// A collection that has all statically available values.
    ///
    /// These may be altered when used to better represent all
    /// available values within the current context.
    @MainActor
    static let all: ItemFilterCollection = .init(
        categories: ChannelCategory.allCases,
        letter: ItemLetter.allCases,
        sortBy: ItemSortBy.supportedCases,
        sortOrder: ItemSortOrder.allCases,
        traits: ItemTrait.supportedCases
    )
}
