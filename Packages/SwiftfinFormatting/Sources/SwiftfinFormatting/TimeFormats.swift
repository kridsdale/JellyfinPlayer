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

public struct MinuteSecondsFormatStyle: FormatStyle {

    public init() {}

    public func format(_ value: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .abbreviated
        formatter.allowedUnits = [.minute, .second]
        return formatter.string(from: value) ?? "--"
    }
}

public extension FormatStyle where Self == MinuteSecondsFormatStyle {

    @available(*, deprecated, message: "Use `Duration` instead.")
    static var minuteSeconds: MinuteSecondsFormatStyle {
        MinuteSecondsFormatStyle()
    }
}

public extension FormatStyle where Self == Duration.UnitsFormatStyle {

    static var minuteSecondsAbbreviated: Duration.UnitsFormatStyle {
        Duration.UnitsFormatStyle(
            allowedUnits: [.minutes, .seconds],
            width: .abbreviated
        )
    }

    static var hourMinuteAbbreviated: Duration.UnitsFormatStyle {
        Duration.UnitsFormatStyle(
            allowedUnits: [.hours, .minutes],
            width: .abbreviated
        )
    }

    static var minuteSecondsNarrow: Duration.UnitsFormatStyle {
        Duration.UnitsFormatStyle(
            allowedUnits: [.minutes, .seconds],
            width: .narrow
        )
    }
}

public struct RuntimeFormatStyle: FormatStyle {

    public init() {}

    public func format(_ value: Duration) -> String {

        let formatStyle: Duration.TimeFormatStyle = if value.components.seconds.magnitude >= 3600 {
            Duration.TimeFormatStyle(pattern: .hourMinuteSecond)
        } else {
            Duration.TimeFormatStyle(pattern: .minuteSecond)
        }

        return formatStyle.format(value)
    }
}

public extension FormatStyle where Self == RuntimeFormatStyle {

    static var runtime: RuntimeFormatStyle {
        RuntimeFormatStyle()
    }
}
