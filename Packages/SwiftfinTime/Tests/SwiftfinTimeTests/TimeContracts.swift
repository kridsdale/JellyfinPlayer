//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation
import SwiftfinTime
import Testing

struct TimeContracts {
    @Test
    func `legacy tick quantization truncates toward zero at one microsecond`() {
        // Captured from the original app helper before extraction, including negative input.
        for (input, expected) in [(-21, -20), (-19, -10), (-1, 0), (0, 0), (1, 0), (19, 10), (21, 20)] {
            #expect(Duration.ticks(input).ticks == expected)
        }
        #expect(Duration.ticks(Int.max).ticks == Int.max / 10 * 10)
        #expect(Duration.ticks(Int.min).ticks == Int.min / 10 * 10)
    }

    @Test
    func `fractional and negative values retain subsecond components`() {
        for seconds in [1.5, -1.5, 0.25, -0.25] {
            let value = Duration.seconds(seconds)
            #expect(value.seconds == seconds)
            #expect(value.microseconds == Int64(seconds * 1_000_000))
            #expect(value.ticks == Int(seconds * 10_000_000))
            #expect(value.minutes == seconds / 60 && value.hours == seconds / 3600)
        }
        #expect(Duration.nanoseconds(1999).microseconds == 1)
        #expect(Duration.nanoseconds(-1999).microseconds == -1)
    }

    @Test
    func `generic minute and hour inputs preserve scale and sign`() {
        #expect(Duration.minutes(Int32(2)).seconds == 120)
        #expect(Duration.minutes(Float(1.5)).seconds == 90)
        #expect(Duration.hours(UInt8(2)).seconds == 7200)
        #expect(Duration.hours(-0.25).seconds == -900)
    }

    @Test
    func `magnitude uses duration arithmetic without converting to floating point`() {
        #expect(abs(Duration.seconds(-1.5)) == .seconds(1.5))
        #expect(abs(Duration.nanoseconds(-1)) == .nanoseconds(1))
        #expect(abs(Duration.zero) == .zero)
    }

    @Test
    func `clock time projection keeps hours and minutes and drops seconds`() {
        let duration = Duration.hours(14) + .minutes(45) + .seconds(59)
        let date = duration.timeOfDayDate
        let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
        #expect(parts.hour == 14 && parts.minute == 45)
        #expect(Duration.timeOfDay(date) == .hours(14) + .minutes(45))
    }

    @Test
    func `conversion values cross executors and keep duration coding`() async throws {
        let value = Duration.hours(1.25)
        let bytes = try JSONEncoder().encode(value)
        let result = await Task.detached { (value.ticks, value.seconds) }.value
        #expect(result.0 == 45_000_000_000 && result.1 == 4500)
        #expect(try JSONDecoder().decode(Duration.self, from: bytes) == value)
    }
}
