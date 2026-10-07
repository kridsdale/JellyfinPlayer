//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import CryptoKit
import Foundation
import JellyfinAPI
import SwiftfinMediaTracks
import SwiftfinPlaybackProfiles
import Testing

private func stream(
    _ index: Int?,
    _ type: MediaStreamType,
    codec: String = "aac",
    external: Bool = false,
    text: Bool = false,
    method: SubtitleDeliveryMethod? = nil
) -> MediaStream {
    var s = MediaStream()
    s.index = index
    s.type = type
    s.codec = codec
    s.isExternal = external
    s.isTextSubtitleStream = text
    s.deliveryMethod = method
    return s
}

private func profile() -> DeviceProfile {
    var p = DeviceProfile()
    var direct = DirectPlayProfile()
    direct.type = .video
    direct.container = "mkv"
    direct.audioCodec = "aac"
    p.directPlayProfiles = [direct]
    p.subtitleProfiles = [.init(format: "srt", method: .embed), .init(format: "srt", method: .external)]
    return p
}

private func source(_ streams: [MediaStream], transcode: Bool = false) -> MediaSourceInfo {
    var s = MediaSourceInfo()
    s.mediaStreams = streams
    s.container = "mkv"
    s.transcodingURL = transcode ? "/synthetic-transcode" : nil
    return s
}

@Test
func `filtering uses snapshot and preserves existing subtitle rules`() {
    let media = source([
        stream(0, .video),
        stream(1, .audio),
        stream(2, .audio, external: true),
        stream(3, .subtitle, codec: "srt", external: true, text: true),
        stream(4, .subtitle, codec: "pgs", external: true),
        stream(5, .subtitle, codec: "srt", method: .drop),
        stream(6, .subtitle, codec: "srt")
    ])
    let direct = MediaTrackPolicy(mediaSource: media, deviceProfile: profile(), compatibility: .directPlay)
    #expect(direct.audioStreams.map(\.index) == [1])
    #expect(direct.videoStreams.map(\.index) == [0])
    #expect(direct.subtitleStreams.map(\.index) == [3, 6])
    let auto = MediaTrackPolicy(mediaSource: media, deviceProfile: profile(), compatibility: .auto)
    #expect(auto.subtitleStreams.map(\.index) == [3, 4, 6])
    #expect(direct.subtitleStreams.map(\.index) == [3, 6])
}

@Test
func `default selection and overrides retain exact installed precedence`() {
    var media = source([stream(7, .audio), stream(8, .subtitle, codec: "srt")])
    media.defaultAudioStreamIndex = 9
    media.defaultSubtitleStreamIndex = 10
    let defaults = MediaTrackPolicy(mediaSource: media, deviceProfile: profile(), compatibility: .auto)
    #expect(defaults.selectedAudioIndex == 9)
    #expect(defaults.selectedSubtitleIndex == 10)
    let override = MediaTrackPolicy(mediaSource: media, deviceProfile: profile(), compatibility: .auto, audioIndex: 7, subtitleIndex: -1)
    #expect(override.selectedAudioIndex == 7)
    #expect(override.selectedSubtitleIndex == -1)
    let empty = MediaTrackPolicy(mediaSource: source([]), deviceProfile: profile(), compatibility: .auto)
    #expect(empty.selectedAudioIndex == 0)
    #expect(empty.selectedSubtitleIndex == -1)
}

@Test
func `direct and transcode index maps keep separate track arrays and selected audio`() {
    let streams = [
        stream(10, .video),
        stream(11, .audio),
        stream(12, .subtitle, codec: "srt"),
        stream(13, .audio),
        stream(14, .subtitle, codec: "srt"),
        stream(15, .subtitle, external: true)
    ]
    let direct = MediaTrackIndexMap.build(from: streams, for: .directPlay, selectedAudioStreamIndex: 13)
    #expect(direct.playerIndex(for: 11) == 0)
    #expect(direct.playerIndex(for: 13) == 1)
    #expect(direct.playerIndex(for: 12) == 0)
    #expect(direct.playerIndex(for: 14) == 1)
    #expect(direct.playerIndex(for: 15) == nil)
    #expect(direct.playerIndex(for: nil) == -1)
    #expect(direct.playerIndex(for: -1) == -1)
    let transcode = MediaTrackIndexMap.build(from: streams, for: .transcode, selectedAudioStreamIndex: 13)
    #expect(transcode.playerIndex(for: 13) == 0)
    #expect(transcode.playerIndex(for: 11) == nil)
    #expect(transcode.playerIndex(for: 12) == nil)
}

@Test
func `missing track indexes do not change enumeration positions`() {
    let map = MediaTrackIndexMap.build(from: [stream(nil, .audio), stream(7, .audio)], for: .directPlay, selectedAudioStreamIndex: 7)
    #expect(map.playerIndex(for: 7) == 1)
    var copy = map
    copy.setPlayerIndex(22, for: 7)
    #expect(map.playerIndex(for: 7) == 1)
    #expect(copy.playerIndex(for: 7) == 22)
}

@Test
func `audio rebuild decisions are pure profile and source policy`() throws {
    let media = source([stream(1, .audio), stream(2, .audio, codec: "unsupported")])
    let direct = MediaTrackPolicy(mediaSource: media, deviceProfile: profile(), compatibility: .auto)
    #expect(!direct.requiresRebuild(type: .audio, from: 2, to: 1))
    #expect(direct.requiresRebuild(type: .audio, from: 1, to: 2))
    #expect(direct.requiresRebuild(type: .audio, from: 1, to: 99))
    let transcode = try MediaTrackPolicy(
        mediaSource: source(#require(media.mediaStreams), transcode: true),
        deviceProfile: profile(),
        compatibility: .auto
    )
    #expect(transcode.requiresRebuild(type: .audio, from: 1, to: 1))
    #expect(!transcode.requiresRebuild(type: .audio, from: 1, to: -1))
    #expect(!transcode.requiresRebuild(type: .audio, from: 1, to: nil))
}

@Test
func `subtitle rebuild decisions cover encoded embedded and external formats`() {
    let streams = [
        stream(1, .subtitle, codec: "srt", method: .encode),
        stream(2, .subtitle, codec: "srt"),
        stream(3, .subtitle, codec: "srt", external: true),
        stream(4, .subtitle, codec: "pgs", external: true)
    ]
    let policy = MediaTrackPolicy(mediaSource: source(streams), deviceProfile: profile(), compatibility: .auto)
    #expect(policy.requiresRebuild(type: .subtitle, from: 1, to: 2))
    #expect(!policy.requiresRebuild(type: .subtitle, from: 2, to: 3))
    #expect(policy.requiresRebuild(type: .subtitle, from: 2, to: 4))
    #expect(!policy.requiresRebuild(type: .subtitle, from: 2, to: 2))
    #expect(!policy.requiresRebuild(type: .subtitle, from: 2, to: 99))
    #expect(!policy.requiresRebuild(type: .subtitle, from: 1, to: -1)) // Preserve the existing early disable rule.
    let transcode = MediaTrackPolicy(mediaSource: source(streams, transcode: true), deviceProfile: profile(), compatibility: .auto)
    #expect(transcode.requiresRebuild(type: .subtitle, from: 2, to: 2))
    #expect(!policy.requiresRebuild(type: .video, from: nil, to: 0))
}

@Test
func `hls external subtitles are accepted and old policy is not mutated`() {
    var p = profile()
    p.subtitleProfiles = [.init(format: "srt", method: .hls)]
    let policy = MediaTrackPolicy(
        mediaSource: source([stream(2, .subtitle, codec: "srt", external: true)]),
        deviceProfile: p,
        compatibility: .auto
    )
    #expect(!policy.requiresRebuild(type: .subtitle, from: nil, to: 2))
    p.subtitleProfiles = []
    #expect(!policy.requiresRebuild(type: .subtitle, from: nil, to: 2))
}

@Test
func `sidecar map matches full url and rejects incorrect hash or invalid player index`() throws {
    let url = try #require(URL(string: "https://localhost.invalid/subtitle?api_key=synthetic"))
    let hash = Insecure.MD5.hash(data: Data(url.absoluteString.utf8)).map { String(format: "%02x", $0) }.joined()
    let original = MediaTrackIndexMap([1: 0, 5: 3])
    let mapped = original.resolvingSidecarSubtitles(
        [(5, url)],
        subtitleTracks: [(-1, hash + "/spu/0"), (7, "wrong/spu/0"), (9, hash + "/spu/2")]
    )
    #expect(mapped.playerIndex(for: 5) == 9)
    #expect(original.playerIndex(for: 5) == 3)
    let changedUrl = try #require(URL(string: "https://localhost.invalid/subtitle?api_key=replacement"))
    #expect(mapped.resolvingSidecarSubtitles([(5, changedUrl)], subtitleTracks: [(9, hash + "/spu/2")]).playerIndex(for: 5) == nil)
}

@Test
func `track snapshot and maps transfer to worker executor`() async {
    let policy = MediaTrackPolicy(mediaSource: source([stream(1, .audio)]), deviceProfile: profile(), compatibility: .auto)
    let result = await Task.detached { policy.initialIndexMap.playerIndex(for: policy.selectedAudioIndex) }.value
    #expect(result == 0)
}

@Test
func `raw source projections preserve nil versus empty lists`() {
    let missing = MediaSourceInfo()
    #expect(missing.audioStreams == nil && missing.subtitleStreams == nil && missing.videoStreams == nil)
    let empty = source([])
    #expect(empty.audioStreams == [] && empty.subtitleStreams == [] && empty.videoStreams == [])
}

@Test
func `raw source projections keep order and external streams without applying player policy`() {
    let media = source([
        stream(4, .audio, external: true),
        stream(2, .video),
        stream(8, .subtitle, codec: "pgs", external: true),
        stream(1, .audio),
        stream(9, .subtitle, method: .drop)
    ])
    #expect(media.audioStreams?.map(\.index) == [4, 1])
    #expect(media.videoStreams?.map(\.index) == [2])
    #expect(media.subtitleStreams?.map(\.index) == [8, 9])
    let playback = MediaTrackPolicy(mediaSource: media, deviceProfile: profile(), compatibility: .directPlay)
    #expect(playback.audioStreams.map(\.index) == [1])
    #expect(playback.subtitleStreams.isEmpty)
}
