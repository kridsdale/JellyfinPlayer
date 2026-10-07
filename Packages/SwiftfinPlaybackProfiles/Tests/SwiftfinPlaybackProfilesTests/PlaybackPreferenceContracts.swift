//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation
import SwiftfinPlaybackProfiles
import Testing

struct PlaybackPreferenceContracts {
    @Test
    func `frozen preference values retain their original encoding`() throws {
        let url = try #require(Bundle.module.url(forResource: "legacy-playback-values", withExtension: "json"))
        let values = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let decoder = JSONDecoder()
        let speed = try #require(values["speed"] as? String)
        #expect(try decoder.decode(PlaybackSpeed.self, from: Data(speed.utf8)) == .custom(1.375))
        let quarter = try #require(values["speedQuarterJSON"] as? String)
        #expect(try decoder.decode(PlaybackSpeed.self, from: Data(quarter.utf8)) == .quarter)
        let bitrate = try #require(values["bitrate"] as? String)
        #expect(try decoder.decode(PlaybackBitrate.self, from: Data(bitrate.utf8)) == .mbps10)
        let jump = try #require(values["jump"] as? String)
        #expect(try decoder.decode(MediaJumpInterval.self, from: Data(jump.utf8)) == .custom(interval: .seconds(7.5)))
        let five = try #require(values["jumpFiveJSON"] as? String)
        #expect(try decoder.decode(MediaJumpInterval.self, from: Data(five.utf8)) == .five)
        #expect(try String(data: JSONEncoder().encode(PlaybackSpeed.custom(1.375)), encoding: .utf8) == speed)
        #expect(try String(data: JSONEncoder().encode(PlaybackBitrate.mbps10), encoding: .utf8) == bitrate)
        let originalJump = try #require(JSONSerialization.jsonObject(with: Data(jump.utf8)) as? NSDictionary)
        let encodedJump = try #require(JSONSerialization
            .jsonObject(with: JSONEncoder().encode(MediaJumpInterval.custom(interval: .seconds(7.5)))) as? NSDictionary)
        #expect(originalJump == encodedJump)
    }

    @Test
    func `bitrate selection preserves floor minimum and caller subset`() {
        #expect(PlaybackBitrate(for: 7_000_000) == .mbps6)
        #expect(PlaybackBitrate(for: -1) == .kbps64)
        #expect(PlaybackBitrate(for: Int.max) == .max)
        #expect(PlaybackBitrate(for: 900_000, in: [.mbps2, .auto, .kbps720, .mbps1, .kbps720]) == .kbps720)
        #expect(PlaybackBitrate(for: 1, in: [.mbps2, .mbps1]) == .mbps1)
        #expect(PlaybackBitrate(for: 1, in: [.auto]) == .auto)
        #expect(PlaybackBitrate(for: 1, in: []) == .auto)
    }

    @Test
    func `source limits preserve video precedence and automatic maximum policy`() {
        #expect(PlaybackBitrate.available(hasVideo: true, hasAudio: true, sourceBitrate: nil) == PlaybackBitrate.videoBitrates)
        #expect(PlaybackBitrate.available(hasVideo: false, hasAudio: true, sourceBitrate: nil) == PlaybackBitrate.audioBitrates)
        #expect(PlaybackBitrate.available(hasVideo: false, hasAudio: false, sourceBitrate: nil) == PlaybackBitrate.allCases)
        #expect(PlaybackBitrate.available(hasVideo: true, hasAudio: true, sourceBitrate: 1_000_000) == [.auto, .max, .kbps720, .kbps420])
        #expect(PlaybackBitrate.available(hasVideo: true, hasAudio: false, sourceBitrate: -1) == [.max])
        #expect(PlaybackBitrate.available(hasVideo: false, hasAudio: true, sourceBitrate: -1).isEmpty)
    }

    @Test
    func `custom values can cross executors without settings or UI`() async {
        let speed = PlaybackSpeed(rawValue: 1.375)
        let interval = MediaJumpInterval(rawValue: .milliseconds(7500))
        let result = await Task.detached { (speed, interval, PlaybackBitrateTestSize.regular) }.value
        #expect(result.0 == .custom(1.375))
        #expect(result.1 == .custom(interval: .seconds(7.5)))
        #expect(result.2.rawValue == 5_000_000)
        #expect(PlaybackSpeed.allCases.map(\.rawValue) == [0.25, 0.5, 0.75, 1, 1.25, 1.5, 1.75, 2])
        #expect(MediaJumpInterval.allCases.map(\.rawValue) == [.seconds(5), .seconds(10), .seconds(15), .seconds(30)])
    }
}
