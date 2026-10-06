//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation

public enum MediaContainer: String, CaseIterable, Codable, Sendable {

    case avi
    case flv
    case m4v
    case mkv
    case mov
    case mp4
    case mpegts
    case ts
    case threeG2 = "3g2"
    case threeGP = "3gp"
    case webm
}
