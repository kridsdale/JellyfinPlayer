//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation
import SwiftfinLocalization
import SwiftfinPlaybackProfiles
import SwiftfinStoredValues

typealias PlaybackBitrateTestSize = SwiftfinPlaybackProfiles.PlaybackBitrateTestSize

extension PlaybackBitrateTestSize: Displayable {
    var displayTitle: String {
        switch self {
        case .largest:
            L10n.largest
        case .larger:
            L10n.larger
        case .regular:
            L10n.regular
        case .smaller:
            L10n.smaller
        case .smallest:
            L10n.smallest
        }
    }
}
