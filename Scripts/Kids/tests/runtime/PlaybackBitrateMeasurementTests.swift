//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation

enum MeasurementTestFailure: Error { case failed }
@main
struct PlaybackBitrateMeasurementTests {
    static func expect(_ value: Bool) throws {
        if !value {
            throw MeasurementTestFailure.failed
        }
    }

    static func main() throws {
        // Received bytes, not the requested test size, determine the estimate.
        try expect(try PlaybackBitrateMeasurement.estimate(bytes: 8_388_608, elapsed: .seconds(1)) == 67_108_864)
        try expect(try PlaybackBitrateMeasurement.estimate(bytes: 1_000_000, elapsed: .milliseconds(500)) == 16_000_000)
        try expect(try PlaybackBitrateMeasurement.estimate(bytes: 1, elapsed: .seconds(100)) == 420_000)
        try expect(try PlaybackBitrateMeasurement.estimate(bytes: Int.max, elapsed: .nanoseconds(1)) == Int(Int32.max))
        for (bytes, elapsed) in [(0, Duration.seconds(1)), (-1, .seconds(1)), (8, .zero), (8, .seconds(-1))] {
            do {
                _ = try PlaybackBitrateMeasurement.estimate(bytes: bytes, elapsed: elapsed)
                throw MeasurementTestFailure.failed
            } catch PlaybackBitrateMeasurement.Failure.invalidMeasurement {}
        }
        print("PASS: received-payload sizing, fractional monotonic durations, bounded conversion, invalid/empty samples")
    }
}
