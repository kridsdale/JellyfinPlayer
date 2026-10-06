//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation

public enum HEVCProfile: String, Codable, Sendable {
    case main
    case main10 = "main 10"
    case main12 = "main 12"
    case mainStill = "main still picture"
    case rext
}
