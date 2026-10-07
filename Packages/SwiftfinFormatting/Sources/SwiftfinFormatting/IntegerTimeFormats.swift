//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation

public extension FixedWidthInteger {
    var timeLabel: String {
        // Dividing in stages supports narrow integers without constructing 3600 in their type.
        let hours = self / 60 / 60
        let minutes = (self / 60) % 60
        let seconds = self % 60
        func padded(_ value: Self) -> String {
            let text = String(value)
            return text.count < 2 ? "0" + text : text
        }
        let hourText = hours > 0 ? String(hours) + ":" : ""
        let minutesText = (hours > 0 ? padded(minutes) : String(minutes)) + ":"
        return hourText + minutesText + padded(seconds)
    }
}

public extension Int {
    /// Preserves the original first-digit remainder display (including 1 ms → 0.1s).
    var millisecondLabel: String {
        let value = magnitude
        let fraction = String(value % 1000).first ?? "0"
        return (self < 0 ? "-" : "") + String(value / 1000) + "." + String(fraction) + "s"
    }

    var secondLabel: String {
        (self < 0 ? "-" : "") + String(magnitude) + "s"
    }
}

public struct MillisecondLabelFormatStyle: FormatStyle, Sendable {
    public init() {}
    public func format(_ value: Int) -> String {
        value.millisecondLabel
    }
}

public struct SecondLabelFormatStyle: FormatStyle, Sendable {
    public init() {}
    public func format(_ value: Int) -> String {
        value.secondLabel
    }
}
