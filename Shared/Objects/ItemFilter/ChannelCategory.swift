//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import SwiftfinFilters
import SwiftfinLocalization

extension ChannelCategory: Displayable, ItemFilter {
    var displayTitle: String {
        switch self {
        case .movies:
            L10n.movies
        case .series:
            L10n.series
        case .news:
            L10n.news
        case .kids:
            L10n.kids
        case .sports:
            L10n.sports
        }
    }
}
