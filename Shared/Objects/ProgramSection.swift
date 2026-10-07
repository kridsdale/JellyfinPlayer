//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import SwiftfinLocalization
import SwiftfinMediaCatalog

typealias ProgramSection = MediaProgramCategory

extension MediaProgramCategory: Displayable {

    var displayTitle: String {
        switch self {
        case .kids:
            L10n.kids
        case .movies:
            L10n.movies
        case .news:
            L10n.news
        case .series:
            L10n.series
        case .sports:
            L10n.sports
        }
    }
}
