//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation
import JellyfinAPI
import SwiftfinPlaybackProfiles
import Testing

private func canonical(_ value: some Encodable) throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    return try encoder.encode(value)
}

private func capabilities(_ mask: Int) -> PlaybackCapabilitySnapshot {
    .init(
        supportsAV1: mask & 1 != 0,
        supportsHEVC: mask & 2 != 0,
        supportsVP9: mask & 4 != 0,
        supportsHLG: mask & 8 != 0,
        supportsHDR10: mask & 16 != 0,
        supportsDolbyVision: mask & 32 != 0,
        hdrEnabled: mask & 64 != 0
    )
}

@Test
func `all 97 original profiles remain identical after library and snapshot extraction`() throws {
    let url = try #require(Bundle.module.url(forResource: "legacy-profiles", withExtension: "json"))
    let frozen = try JSONDecoder().decode([String: DeviceProfile].self, from: Data(contentsOf: url))
    #expect(frozen.count == 97)
    var names = Set<String>()
    for player in VideoPlayerType.allCases {
        for mode in PlaybackCompatibility.allCases {
            for mask in [0, 127] {
                for action in [CustomDeviceProfileAction.add, .replace] {
                    for transcode in [false, true] {
                        let name = "\(player.rawValue)-\(mode.rawValue)-\(mask)-\(action.rawValue)-\(transcode)"
                        let settings = PlaybackProfileSettings(customAction: action, customProfiles: [
                            CustomDeviceProfile(
                                type: .video,
                                useAsTranscodingProfile: transcode,
                                audio: [.aac],
                                video: [.h264],
                                container: [.mp4]
                            ),
                            CustomDeviceProfile(type: .audio, audio: [.mp3])
                        ])
                        let actual = DeviceProfile.build(
                            for: player,
                            compatibilityMode: mode,
                            maxBitrate: 8_000_000,
                            maxResolution: .p1080,
                            settings: settings,
                            capabilities: capabilities(mask)
                        )
                        let expected = try #require(frozen[name])
                        #expect(try canonical(actual) == canonical(expected), Comment(rawValue: name))
                        names.insert(name)
                    }
                }
            }
        }
    }
    let burn = DeviceProfile.build(
        for: .vlc,
        compatibilityMode: .auto,
        settings: .init(forceSubtitleBurnIn: true),
        capabilities: capabilities(0)
    )
    #expect(try canonical(burn) == canonical(#require(frozen["burn-all-subtitles"])))
    names.insert("burn-all-subtitles")
    #expect(names == Set(frozen.keys))
}

@Test
func `profile assembly transfers immutable input snapshots to a worker executor`() async throws {
    let hardware = capabilities(127)
    let settings = PlaybackProfileSettings(forceSubtitleBurnIn: true)
    let background = await Task.detached { DeviceProfile.build(
        for: .native,
        compatibilityMode: .auto,
        settings: settings,
        capabilities: hardware
    ) }.value
    let foreground = DeviceProfile.build(for: .native, compatibilityMode: .auto, settings: settings, capabilities: hardware)
    #expect(try canonical(background) == canonical(foreground))
}

@Test
func `snapshot replacements cannot mutate a previously assembled profile`() throws {
    let before = DeviceProfile.build(for: .native, compatibilityMode: .auto, settings: .init(), capabilities: capabilities(0))
    let bytes = try canonical(before)
    let after = DeviceProfile.build(
        for: .native,
        compatibilityMode: .auto,
        settings: .init(forceSubtitleBurnIn: true),
        capabilities: capabilities(127)
    )
    #expect(try canonical(before) == bytes)
    #expect(try canonical(after) != bytes)
    #expect(before.subtitleProfiles?.contains { $0.method != .encode } == true)
    #expect(after.subtitleProfiles?.allSatisfy { $0.method == .encode } == true)
}

@Test
func `direct capability checks retain CSV wildcards case handling and subtitle methods`() {
    var profile = DeviceProfile()
    profile.directPlayProfiles = [DirectPlayProfile(audioCodec: "aac, AC3", container: "mkv, mp4", type: .video, videoCodec: "h264, hevc")]
    #expect(profile.canPlay(type: .video, videoCodec: "HEVC", container: "MKV"))
    #expect(profile.canPlay(type: .video, audioCodec: "ac3", container: "mp4"))
    #expect(!profile.canPlay(type: .audio, audioCodec: "ac3", container: "mp4"))
    #expect(!profile.canPlay(type: .video, videoCodec: "av1", container: "mkv"))
    profile.directPlayProfiles = [DirectPlayProfile(type: .video)]
    #expect(profile.canPlay(type: .video, videoCodec: nil, container: nil))
    profile.subtitleProfiles = [SubtitleProfile(format: "subrip", method: .external)]
    #expect(profile.canPlay(subtitleFormat: "SUBRIP", method: .external))
    #expect(!profile.canPlay(subtitleFormat: nil, method: .external))
    #expect(!profile.canPlay(subtitleFormat: "subrip", method: .encode))
}

@Test
func `encoded playback value raw identities and subtitle classifications remain stable`() throws {
    #expect(try canonical(MediaContainer.threeGP) == Data(#""3gp""#.utf8))
    #expect(try canonical(VideoPlayerType.vlc) == Data(#""vlc""#.utf8))
    #expect(try canonical(PlaybackResolution.p1080) == Data("1080".utf8))
    let legacy = Data(#"{"type":"Video","useAsTranscodingProfile":true,"audio":["aac"],"video":["h264"],"container":["mp4"]}"#.utf8)
    let profile = try JSONDecoder().decode(CustomDeviceProfile.self, from: legacy)
    #expect(profile.type == .video && profile.useAsTranscodingProfile && profile.audio == [.aac] && profile.container == [.mp4])
    #expect(SubtitleFormat(url: URL(fileURLWithPath: "/synthetic.SRT")) == .subrip)
    #expect(SubtitleFormat.subrip.isText && !SubtitleFormat.pgssub.isText)
}
