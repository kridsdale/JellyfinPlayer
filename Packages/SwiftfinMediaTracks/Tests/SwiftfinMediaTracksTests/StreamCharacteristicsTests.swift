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

@Suite("Inherited stream characteristics")
struct StreamCharacteristicsTests {
    @Test
    func `resolution cutoffs and missing dimensions keep inherited behavior`() {
        for (width, hd, fourK) in [(0, false, false), (1900, false, false), (1901, true, false), (3800, true, false), (3801, true, true)] {
            var stream = MediaStream()
            stream.width = width
            stream.type = .video
            #expect(stream.isHDVideo == hd && stream.is4kVideo == fourK)
            stream.type = .audio
            #expect(!stream.isHDVideo && !stream.is4kVideo)
        }
        #expect(!MediaStream().isHDVideo && !MediaStream().is4kVideo)
    }

    @Test
    func `audio layouts and collection flags do not invent missing metadata`() {
        var five = MediaStream(), seven = MediaStream()
        five.channelLayout = "5.1"
        seven.channelLayout = "7.1"
        #expect(five.is51AudioChannelLayout && !five.is71AudioChannelLayout)
        #expect(seven.is71AudioChannelLayout && !seven.is51AudioChannelLayout)
        let values = [five, seven, MediaStream()]
        #expect(values.has51AudioChannelLayout && values.has71AudioChannelLayout)
        #expect(!values.hasHDVideo && !values.has4KVideo && !values.hasSubtitles)
        #expect(![MediaStream]().hasHDRVideo && ![MediaStream]().hasDolbyVision)
        five.channelLayout = "5.1(side)"
        #expect(!five.is51AudioChannelLayout)
        seven.type = .subtitle
        #expect([seven].hasSubtitles)
    }

    @Test
    func `all inherited range cases retain their HDR and Dolby Vision classification`() {
        let cases: [(VideoRangeType, Bool, Bool)] = [
            (.unknown, false, false), (.sdr, false, false), (.hdr10, true, false), (.hlg, true, false),
            (.dovi, true, true), (.doviWithEL, true, true), (.doviWithELHDR10Plus, true, true),
            (.doviWithHDR10, true, true), (.doviWithHDR10Plus, true, true), (.doviWithHLG, true, true),
            (.doviInvalid, false, false), (.doviWithSDR, true, true), (.hdr10Plus, true, false)
        ]
        for (range, hdr, dolby) in cases {
            #expect(range.isHDR == hdr && range.isDolbyVision == dolby)
            var stream = MediaStream()
            stream.videoRangeType = range
            #expect([stream].hasHDRVideo == hdr && [stream].hasDolbyVision == dolby)
        }
    }

    @Test
    func `sidecar selection preserves order missing index and exact external text conditions`() {
        func subtitle(_ index: Int?, method: SubtitleDeliveryMethod?, path: String?, text: Bool?) -> MediaStream {
            var stream = MediaStream()
            stream.index = index
            stream.deliveryMethod = method
            stream.deliveryURL = path
            stream.isTextSubtitleStream = text
            return stream
        }
        let streams = [
            subtitle(9, method: .external, path: "/nine", text: true),
            subtitle(1, method: .external, path: "/bitmap", text: false),
            subtitle(2, method: .embed, path: "/embed", text: true),
            subtitle(3, method: .external, path: nil, text: true),
            subtitle(nil, method: .external, path: "/unindexed", text: true),
            subtitle(4, method: .external, path: "/unknown-text", text: nil),
            subtitle(5, method: .drop, path: "/drop", text: true),
            subtitle(6, method: .external, path: "", text: true)
        ]
        // URL validity is a separate preparation concern. This pure filter
        // deliberately preserves the legacy optional URL and index semantics.
        #expect(streams.sidecarSubtitles.map(\.index) == [9, nil, 6])
        #expect(streams.map(\.index) == [9, 1, 2, 3, nil, 4, 5, 6])
    }

    @Test
    func `immutable stream projections can run independently of the UI actor`() async {
        var stream = MediaStream()
        stream.type = .video
        stream.width = 3840
        stream.videoRangeType = .doviWithHDR10
        let captured = [stream]
        let result = await Task.detached {
            (captured.has4KVideo, captured.hasHDVideo, captured.hasHDRVideo, captured.hasDolbyVision)
        }.value
        #expect(result.0 && result.1 && result.2 && result.3)
    }
}
