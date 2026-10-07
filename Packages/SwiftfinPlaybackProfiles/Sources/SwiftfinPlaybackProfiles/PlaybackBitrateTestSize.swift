//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation

public enum PlaybackBitrateTestSize: Int, CaseIterable, Codable, Sendable {
    case largest = 10_000_000
    case larger = 7_500_000
    case regular = 5_000_000
    case smaller = 2_500_000
    case smallest = 1_000_000
}
