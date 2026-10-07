//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation
import SwiftfinFormatting
import SwiftfinLocalization
import Testing

struct FormattingContracts {
    private func fixture() throws -> [String: Any] {
        let url = try #require(Bundle.module.url(forResource: "legacy-formatting-values", withExtension: "json"))
        return try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    }

    @Test
    func `original locale outputs retain exact clock bitrate rate and fallback text`() throws {
        let values = try fixture()
        #expect(values["locale"] as? String == "en_US")
        // Numeric/localized golden strings describe the observed original en_US environment.
        if Locale.current.identifier == values["locale"] as? String {
            for row in try #require(values["runtime"] as? [[String: Any]]) {
                let seconds = try #require(row["seconds"] as? Int)
                #expect(RuntimeFormatStyle().format(.seconds(seconds)) == row["text"] as? String)
            }
            for row in try #require(values["bitrate"] as? [[String: Any]]) {
                let raw = try #require(row["raw"] as? Int)
                #expect(IntBitRateFormatStyle().format(raw) == row["text"] as? String)
            }
            for row in try #require(values["speed"] as? [[String: Any]]) {
                let raw = try #require(row["raw"] as? NSNumber)
                #expect(PlaybackRateStyle().format(raw.floatValue) == row["text"] as? String)
            }
            #expect(MinuteSecondsFormatStyle().format(90) == values["minuteSeconds90"] as? String)
            #expect(LastSeenFormatStyle().format(nil) == values["lastSeenNil"] as? String)
        }
        for row in try #require(values["days"] as? [[String: Any]]) {
            let raw = try #require(row["raw"] as? Double)
            #expect(DayIntervalParseableFormatStyle(range: 0 ... 365).format(raw) == row["text"] as? String)
        }
        #expect(NilIfEmptyStringFormatStyle().format(nil) == values["nilEmpty"] as? String)
    }

    @Test
    func `day editor formatting clamps but parsing retains its original permissive policy`() throws {
        let style = DayIntervalParseableFormatStyle(range: 1 ... 7)
        #expect(style.format(0) == "1" && style.format(20 * 86400) == "7")
        #expect(try style.parseStrategy.parse("2.5") == 216_000)
        #expect(try style.parseStrategy.parse("20") == 1_728_000)
        #expect(try style.parseStrategy.parse("bad") == 0)
        #expect(try style.parseStrategy.parse("-1") == -86400)
    }

    @Test
    func `empty text editor preserves whitespace and only maps empty to nil`() throws {
        let style = NilIfEmptyStringFormatStyle()
        #expect(style.format(nil) == "" && style.format(" ") == " ")
        #expect(try style.parseStrategy.parse("") == nil)
        #expect(try style.parseStrategy.parse(" ") == " ")
        #expect(VerbatimFormatStyle<Int>().format(42) == "42")
    }

    @Test
    func `copied age style retains its original and uses the selected end date`() throws {
        let parser = ISO8601DateFormatter()
        let birth = try #require(parser.date(from: "2000-01-01T12:00:00Z"))
        let death = try #require(parser.date(from: "2010-01-01T12:00:00Z"))
        let original = AgeFormatStyle()
        let dated = original.death(death)
        #expect(dated.format(birth) == L10n.yearsOld(10))
        let yearsNow = Calendar.current.dateComponents([.year], from: birth, to: .now).year ?? 0
        #expect(original.format(birth) == L10n.yearsOld(yearsNow))
        #expect(LastSeenFormatStyle().format(nil) == L10n.never)
        #expect(original != dated)
    }

    @Test
    func `bitrate display uses decimal units and retains its largest unit limit`() {
        #expect(IntBitRateFormatStyle().format(999) == "999.0 " + L10n.bitsPerSecond)
        #expect(IntBitRateFormatStyle().format(1000) == "1.0 " + L10n.kilobitsPerSecond)
        #expect(IntBitRateFormatStyle().format(1_000_000) == "1.0 " + L10n.megabitsPerSecond)
        #expect(IntBitRateFormatStyle().format(Int.max).hasSuffix(" " + L10n.terabitsPerSecond))
    }

    @Test
    func `formatter values cross executors and keep configured coding`() async throws {
        let rate = PlaybackRateStyle(precision: 1)
        let restored = try JSONDecoder().decode(PlaybackRateStyle.self, from: JSONEncoder().encode(rate))
        #expect(restored == rate)
        let result = await Task.detached { (rate.format(1.25), NilIfEmptyStringFormatStyle().format("worker")) }.value
        #expect(result.0.hasSuffix("×") && result.1 == "worker")
    }
}
