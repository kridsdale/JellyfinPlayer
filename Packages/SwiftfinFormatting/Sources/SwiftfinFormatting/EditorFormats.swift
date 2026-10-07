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

public struct VerbatimFormatStyle<Value: CustomStringConvertible>: FormatStyle {

    public init() {}

    public func format(_ value: Value) -> String {
        value.description
    }
}

public extension FormatStyle where Self == PlaybackRateStyle {

    static var playbackRate: PlaybackRateStyle {
        PlaybackRateStyle()
    }

    static func playbackRate(precision: Int) -> PlaybackRateStyle {
        PlaybackRateStyle(precision: precision)
    }
}

public struct PlaybackRateStyle: FormatStyle {

    private let precision: Int

    public init(precision: Int = 2) {
        self.precision = precision
    }

    public func format(_ value: Float) -> String {
        FloatingPointFormatStyle<Float>()
            .precision(.fractionLength(0 ... precision))
            .format(value)
            .appending("\u{00D7}")
    }
}

/// Represent intervals as 24 hour, 60 minute, 60 second days
public struct DayIntervalParseableFormatStyle: ParseableFormatStyle {

    public init(range: ClosedRange<Int>) {
        self.range = range
    }

    public let range: ClosedRange<Int>
    public var parseStrategy: DayIntervalParseStrategy = .init()

    public func format(_ value: TimeInterval) -> String {
        "\(clamp(Int(value / 86400), min: range.lowerBound, max: range.upperBound))"
    }
}

public struct DayIntervalParseStrategy: ParseStrategy {

    public init() {}

    public func parse(_ value: String) throws -> TimeInterval {
        (TimeInterval(value) ?? 0) * 86400
    }
}

public extension ParseableFormatStyle where Self == DayIntervalParseableFormatStyle {

    static func dayInterval(range: ClosedRange<Int>) -> DayIntervalParseableFormatStyle {
        .init(range: range)
    }
}

public struct NilIfEmptyStringFormatStyle: ParseableFormatStyle {

    public init() {}

    public var parseStrategy: NilIfEmptyStringParseStrategy = .init()

    public func format(_ value: String?) -> String {
        value ?? ""
    }
}

public struct NilIfEmptyStringParseStrategy: ParseStrategy {

    public init() {}

    public func parse(_ value: String) -> String? {
        value.isEmpty ? nil : value
    }
}

public extension ParseableFormatStyle where Self == NilIfEmptyStringFormatStyle {

    static var nilIfEmptyString: NilIfEmptyStringFormatStyle {
        .init()
    }
}
