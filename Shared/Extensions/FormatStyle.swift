//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation
import SwiftfinFormatting

typealias MinuteSecondsFormatStyle = SwiftfinFormatting.MinuteSecondsFormatStyle
typealias RuntimeFormatStyle = SwiftfinFormatting.RuntimeFormatStyle
typealias VerbatimFormatStyle<Value: CustomStringConvertible> = SwiftfinFormatting.VerbatimFormatStyle<Value>
typealias PlaybackRateStyle = SwiftfinFormatting.PlaybackRateStyle
typealias DayIntervalParseableFormatStyle = SwiftfinFormatting.DayIntervalParseableFormatStyle
typealias DayIntervalParseStrategy = SwiftfinFormatting.DayIntervalParseStrategy
typealias NilIfEmptyStringFormatStyle = SwiftfinFormatting.NilIfEmptyStringFormatStyle
typealias NilIfEmptyStringParseStrategy = SwiftfinFormatting.NilIfEmptyStringParseStrategy
typealias LastSeenFormatStyle = SwiftfinFormatting.LastSeenFormatStyle
typealias AgeFormatStyle = SwiftfinFormatting.AgeFormatStyle
typealias IntBitRateFormatStyle = SwiftfinFormatting.IntBitRateFormatStyle

// This adapter depends on the application's UI display protocol.
struct DisplayableFormatStyle<Value: Displayable>: FormatStyle {

    func format(_ value: Value) -> String {
        value.displayTitle
    }
}
