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

struct PlaybackOptionContracts {
    private func source(_ id: String) throws -> MediaSourceInfo {
        let data = Data("""
        {"Id":"\(id)","Path":"/synthetic/\(id).mkv","Bitrate":80000000,"Container":"mkv", "MediaStreams":[{"Index":7,"Type":"Audio","Language":"en","Codec":"aac"},{"Index":11,"Type":"Subtitle","Language":"fr","Codec":"srt"}]}
        """.utf8)
        return try JSONDecoder().decode(MediaSourceInfo.self, from: data)
    }

    private func payload(_ source: MediaSourceInfo?) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(source)
    }

    @Test
    func `choosing another version retains its complete payload and resets source specific tracks`() throws {
        let originalSource = try source("original"), alternate = try source("alternate")
        let original = PlaybackOptions(
            mediaSource: originalSource, audioStreamIndex: 7, subtitleStreamIndex: 11, requestedBitrate: .mbps40
        )
        let changed = original.selecting(.mediaSource(alternate))
        #expect(try payload(changed.mediaSource) == payload(alternate))
        #expect(changed.audioStreamIndex == nil && changed.subtitleStreamIndex == nil)
        #expect(changed.requestedBitrate == .mbps40)
        let reselected = changed.selecting(.audioStreamIndex(7)).selecting(.subtitleStreamIndex(11)).selecting(.mediaSource(alternate))
        #expect(reselected.audioStreamIndex == nil && reselected.subtitleStreamIndex == nil)
        #expect(try payload(original.mediaSource) == payload(originalSource))
        #expect(original.audioStreamIndex == 7 && original.subtitleStreamIndex == 11)
    }

    @Test
    func `automatic audio disabled subtitles and bitrate changes remain independent until source reset`() throws {
        let originalSource = try source("original")
        let original = PlaybackOptions(
            mediaSource: originalSource, audioStreamIndex: 7, subtitleStreamIndex: 11, requestedBitrate: .max
        )
        let audio = original.selecting(.audioStreamIndex(nil))
        #expect(audio.audioStreamIndex == nil && audio.subtitleStreamIndex == 11)
        #expect(audio.requestedBitrate == .max)
        let subtitles = audio.selecting(.subtitleStreamIndex(-1))
        #expect(subtitles.audioStreamIndex == nil && subtitles.subtitleStreamIndex == -1)
        let automatic = subtitles.selecting(.bitrate(.auto))
        #expect(automatic.subtitleStreamIndex == -1 && automatic.requestedBitrate == .auto)
        #expect(try payload(automatic.mediaSource) == payload(originalSource))
        let reset = automatic.selecting(.mediaSource(nil))
        #expect(reset.mediaSource == nil && reset.audioStreamIndex == nil && reset.subtitleStreamIndex == nil)
        #expect(reset.requestedBitrate == .auto)
        #expect(original.audioStreamIndex == 7 && original.subtitleStreamIndex == 11 && original.requestedBitrate == .max)
    }

    @Test
    func `selection snapshots cross executors without mutating the original or reading platform state`() async throws {
        let original = try PlaybackOptions(
            mediaSource: source("original"), audioStreamIndex: 7, subtitleStreamIndex: -1, requestedBitrate: .mbps20
        )
        let changed = await Task.detached {
            original.selecting(.audioStreamIndex(0)).selecting(.subtitleStreamIndex(nil)).selecting(.bitrate(.mbps10))
        }.value
        #expect(changed.audioStreamIndex == 0 && changed.subtitleStreamIndex == nil && changed.requestedBitrate == .mbps10)
        #expect(try payload(changed.mediaSource) == payload(original.mediaSource))
        #expect(original.audioStreamIndex == 7 && original.subtitleStreamIndex == -1 && original.requestedBitrate == .mbps20)
    }
}
