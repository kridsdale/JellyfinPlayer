//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation
import JellyfinAPI
import SwiftfinMediaTracks
import Testing

struct CategorizedTrackContracts {
    private struct NativeFixture: Decodable {
        let mpvID: Int
        let type: String
        let isExternal: Bool
        let title: String?
        var value: CategorizedMediaTrack {
            .init(
                index: mpvID,
                type: type == "audio" ? .audio : type == "subtitle" ? .subtitle : .video,
                title: title,
                external: isExternal
            )
        }
    }

    private struct Expected: Decodable { let query: Int?
        let player: Int?
    }

    private struct Fixture: Decodable {
        let name: String
        let streams: [MediaStream]
        let tracks: [NativeFixture]
        let transcode: Bool
        let selected: Int?
        let expected: [Expected]
    }

    private struct Capture: Decodable { let originalCommit: String
        let originalSourceSHA256: String
        let cases: [Fixture]
    }

    @Test
    func `categorized mapping matches independently executed frozen original outputs`() throws {
        let url = try #require(Bundle.module.url(forResource: "mpv-original-ed99a83e", withExtension: "json"))
        let capture = try JSONDecoder().decode(Capture.self, from: Data(contentsOf: url))
        #expect(capture.originalCommit == "ed99a83e12c26a4213beb73f7a9ff2f99eb7da97" && capture
            .originalSourceSHA256 == "319ac1ceeaaf978c2ef98b0b9ca1dae325dbd42b26e9e8ed0c61e5e12d050308")
        #expect(capture.cases.count == 9 && capture.cases.reduce(0) { $0 + $1.expected.count } == 144)
        for fixture in capture.cases {
            let map = MediaTrackIndexMap.categorized(
                mediaStreams: fixture.streams,
                tracks: fixture.tracks.map(\.value),
                isTranscoding: fixture.transcode,
                selectedAudioStreamIndex: fixture.selected
            )
            for expected in fixture.expected {
                #expect(
                    map.playerIndex(for: expected.query) == expected.player,
                    Comment(rawValue: fixture.name)
                )
            }
        }
    }

    @Test
    func `sidecars require exact native subtitle external tag and eligible server stream`() {
        var stream = MediaStream()
        stream.index = 8
        stream.type = .subtitle
        stream.isExternal = true
        stream.isTextSubtitleStream = true
        stream.deliveryMethod = .external
        stream.deliveryURL = "/synthetic-sidecar"
        for track in [
            CategorizedMediaTrack(index: 1, type: .audio, title: "swiftfin-subtitle-8", external: true),
            .init(index: 2, type: .subtitle, title: "swiftfin-subtitle-8", external: false),
            .init(index: 3, type: .subtitle, title: "swiftfin-subtitle-80", external: true)
        ] {
            #expect(MediaTrackIndexMap.categorized(
                mediaStreams: [stream],
                tracks: [track],
                isTranscoding: false,
                selectedAudioStreamIndex: nil
            ).playerIndex(for: 8) == nil)
        }
        let tracks: [CategorizedMediaTrack] = [
            .init(index: 4, type: .subtitle, title: "swiftfin-subtitle-8", external: true),
            .init(index: 5, type: .subtitle, title: "swiftfin-subtitle-8", external: true)
        ]
        #expect(MediaTrackIndexMap.categorized(mediaStreams: [stream], tracks: tracks, isTranscoding: false, selectedAudioStreamIndex: nil)
            .playerIndex(for: 8) == 4)
        stream.deliveryURL = nil
        #expect(MediaTrackIndexMap.categorized(mediaStreams: [stream], tracks: tracks, isTranscoding: false, selectedAudioStreamIndex: nil)
            .playerIndex(for: 8) == nil)
    }

    @Test
    func `mapping preserves input arrays and runs without the UI executor`() async {
        var stream = MediaStream()
        stream.index = 12
        stream.type = .audio
        let streams = [stream]
        let tracks: [CategorizedMediaTrack] = [.init(index: 3, type: .audio)]
        let result = await Task.detached { MediaTrackIndexMap.categorized(
            mediaStreams: streams,
            tracks: tracks,
            isTranscoding: false,
            selectedAudioStreamIndex: nil
        ) }.value
        #expect(result.playerIndex(for: 12) == 3 && streams[0].index == 12 && tracks[0].index == 3)
    }
}
