//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation

public enum ItemFilterType: String, CaseIterable, Codable, Hashable, Identifiable, Sendable {
    case audioLanguage
    case genres
    case letter
    case officialRatings
    case sortBy
    case subtitleLanguage
    case tags
    case traits
    case years
    case category
    public var id: String {
        rawValue
    }
}
