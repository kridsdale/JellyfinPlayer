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

typealias PlaybackSpeed = SwiftfinPlaybackProfiles.PlaybackSpeed

extension PlaybackSpeed: Displayable {
    var displayTitle: String {
        rawValue.formatted(.playbackRate(precision: 2))
    }
}
