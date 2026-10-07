//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation
import SwiftfinLocalization
import SwiftfinValues

public struct IntBitRateFormatStyle: FormatStyle {

    public init() {}
    public func format(_ value: Int) -> String {
        let units = [
            L10n.bitsPerSecond,
            L10n.kilobitsPerSecond,
            L10n.megabitsPerSecond,
            L10n.gigabitsPerSecond,
            L10n.terabitsPerSecond,
        ]
        var adjustedValue = Double(value)
        var unitIndex = 0

        while adjustedValue >= 1000, unitIndex < units.count - 1 {
            adjustedValue /= 1000
            unitIndex += 1
        }

        let formattedValue = String(format: "%.1f", adjustedValue)
        return "\(formattedValue) \(units[unitIndex])"
    }
}

public extension FormatStyle where Self == IntBitRateFormatStyle {
    static var bitRate: IntBitRateFormatStyle {
        IntBitRateFormatStyle()
    }
}
