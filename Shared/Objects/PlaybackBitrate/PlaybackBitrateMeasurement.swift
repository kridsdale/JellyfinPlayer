//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

// SPDX-License-Identifier: MPL-2.0
import Foundation

/// Measures the received payload, using monotonic time and bounded conversion.
enum PlaybackBitrateMeasurement {
    enum Failure: Error { case invalidMeasurement }
    static func estimate(bytes: Int, elapsed: Duration) throws -> Int {
        let parts = elapsed.components
        let seconds = Double(parts.seconds) + Double(parts.attoseconds) / 1e18
        guard bytes > 0, seconds.isFinite, seconds > 0 else { throw Failure.invalidMeasurement }
        let rate = Double(bytes) * 8 / seconds
        guard rate.isFinite, rate > 0 else { throw Failure.invalidMeasurement }
        return Int(min(Double(Int32.max), max(420_000, rate)))
    }
}
