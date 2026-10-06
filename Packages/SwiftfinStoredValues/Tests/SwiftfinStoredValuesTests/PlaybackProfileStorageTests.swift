//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Defaults
import Foundation
import SwiftfinPlaybackProfiles
import SwiftfinStoredValues
import Testing

@Suite(.serialized) @MainActor
struct PlaybackProfileStorageTests {
    @Test
    func `frozen raw and JSON defaults from the original app remain readable and writable`() throws {
        let name = "profile-storage-" + UUID().uuidString
        let suite = try #require(UserDefaults(suiteName: name))
        defer { suite.removePersistentDomain(forName: name) }
        // Captured with original production types/Defaults 9.0.9 before extraction.
        suite.set("directPlay", forKey: "compatibility")
        suite.set("\"vlc\"", forKey: "player")
        suite.set("1080", forKey: "resolution")
        let mode = Defaults.Key<PlaybackCompatibility>("compatibility", default: .auto, suite: suite)
        let player = Defaults.Key<VideoPlayerType>("player", default: .native, suite: suite)
        let resolution = Defaults.Key<PlaybackResolution>("resolution", default: .max, suite: suite)
        #expect(Defaults[mode] == .directPlay && Defaults[player] == .vlc && Defaults[resolution] == .p1080)
        Defaults[mode] = .custom
        Defaults[player] = .native
        Defaults[resolution] = .p720
        #expect(suite.string(forKey: "compatibility") == "custom")
        #expect(suite.string(forKey: "player") == "\"native\"")
        #expect(suite.string(forKey: "resolution") == "720")
    }

    @Test
    func `codec stored keys preserve original JSON strings and adjacent values`() throws {
        let name = "codec-storage-" + UUID().uuidString
        let suite = try #require(UserDefaults(suiteName: name))
        defer { suite.removePersistentDomain(forName: name) }
        suite.set("\"h264\"", forKey: "video")
        suite.set("\"3gp\"", forKey: "container")
        suite.set("unchanged", forKey: "adjacent")
        let video = Defaults.Key<VideoCodec>("video", default: .hevc, suite: suite)
        let container = Defaults.Key<MediaContainer>("container", default: .mkv, suite: suite)
        #expect(Defaults[video] == .h264 && Defaults[container] == .threeGP)
        Defaults[video] = .av1
        #expect(suite.string(forKey: "video") == "\"av1\"")
        #expect(suite.string(forKey: "adjacent") == "unchanged")
    }
}
