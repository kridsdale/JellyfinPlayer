//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation
import SwiftfinFormatting
import Testing

struct IntegerTimeContracts {
    @Test
    func `integer labels match independently executed original output including signed clocks`() throws {
        let url = try #require(Bundle.module.url(forResource: "integer-original-98730a81", withExtension: "json"))
        let data = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        #expect(data["sourceCommit"] as? String == "98730a817b51a255f2370e3f5e7b53999c392d7d")
        for row in try #require(data["clock"] as? [[String: Any]]) {
            let raw = try #require((row["value"] as? NSNumber)?.intValue)
            #expect(raw.timeLabel == row["text"] as? String)
        }
        for row in try #require(data["labels"] as? [[String: Any]]) {
            let raw = try #require((row["value"] as? NSNumber)?.intValue)
            #expect(raw.millisecondLabel == row["milliseconds"] as? String)
            #expect(raw.secondLabel == row["seconds"] as? String)
            #expect(MillisecondLabelFormatStyle().format(raw) == raw.millisecondLabel)
            #expect(SecondLabelFormatStyle().format(raw) == raw.secondLabel)
        }
    }

    @Test
    func `minimum integer labels safely represent the full magnitude`() {
        #expect(Int.min.secondLabel == "-9223372036854775808s")
        #expect(Int.min.millisecondLabel == "-9223372036854775.8s")
        #expect(SecondLabelFormatStyle().format(Int.min) == Int.min.secondLabel)
        #expect(MillisecondLabelFormatStyle().format(Int.min) == Int.min.millisecondLabel)
    }

    @Test
    func `generic clocks support narrow and maximum unsigned integers`() {
        #expect(Int8(61).timeLabel == "1:01")
        #expect(Int8(-61).timeLabel == "-1:-1")
        #expect(UInt8.max.timeLabel == "4:15")
        #expect(UInt64.max.timeLabel == "5124095576030431:00:15")
    }

    @Test
    func `integer styles retain coding and operate on independent executors`() async throws {
        let style = MillisecondLabelFormatStyle()
        let restored = try JSONDecoder().decode(MillisecondLabelFormatStyle.self, from: JSONEncoder().encode(style))
        #expect(style == restored)
        let result = await Task.detached { (style.format(-1234), SecondLabelFormatStyle().format(-3)) }.value
        #expect(result.0 == "-1.2s" && result.1 == "-3s")
    }
}
