//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation
import SwiftfinFormatting
import SwiftfinLocalization
import SwiftfinPlaybackProfiles
import SwiftfinStoredValues

typealias MediaJumpInterval = SwiftfinPlaybackProfiles.MediaJumpInterval

extension MediaJumpInterval: Displayable, SystemImageable {
    var displayTitle: String {
        rawValue.formatted(.minuteSecondsNarrow)
    }

    var systemImage: String {
        switch self {
        case .thirty:
            "goforward.30"
        case .fifteen:
            "goforward.15"
        case .ten:
            "goforward.10"
        case .five:
            "goforward.5"
        case .custom:
            "goforward"
        }
    }

    var secondarySystemImage: String {
        switch self {
        case .thirty:
            "gobackward.30"
        case .fifteen:
            "gobackward.15"
        case .ten:
            "gobackward.10"
        case .five:
            "gobackward.5"
        case .custom:
            "gobackward"
        }
    }
}
