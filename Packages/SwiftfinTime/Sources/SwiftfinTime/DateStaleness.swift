//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation

public extension Date {
    /// Wall-clock cache age. A comparison date makes the strict boundary usable
    /// without a mutable clock; existing callers continue to compare with now.
    func isStale(with interval: Duration, comparedTo now: Date = .now) -> Bool {
        now.timeIntervalSince(self) > interval.seconds
    }
}
