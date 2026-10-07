//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import JellyfinAPI
import SwiftfinMediaTracks
import Testing

struct MediaVideoQualityContracts {
    @Test
    func `default selection spans sources and preserves item-first fallback order`() {
        let itemFirst = MediaStream(type: .video, width: 1920)
        let sourceFirst = MediaStream(type: .video, width: 3840)
        let sourceDefault = MediaStream(isDefault: true, type: .video, width: 7680)
        var item = BaseItemDto(mediaSources: [.init(mediaStreams: [sourceFirst, sourceDefault])], mediaStreams: [itemFirst])
        #expect(MediaVideoQuality(item).resolution == .uhd8K)
        item.mediaSources?[0].mediaStreams?[1].isDefault = false
        #expect(MediaVideoQuality(item).resolution == .hd1080)
        item.mediaStreams = nil
        #expect(MediaVideoQuality(item).resolution == .uhd4K)
    }

    @Test
    func `cropped width and tall height retain every poster resolution threshold`() {
        let cases: [(Int, Int, MediaVideoQuality.Resolution?)] = [
            (7680, 1, .uhd8K), (1, 4320, .uhd8K), (3840, 1600, .uhd4K), (1, 2160, .uhd4K),
            (2560, 1, .hd1440), (1, 1440, .hd1440), (1920, 800, .hd1080), (1, 1080, .hd1080),
            (1280, 1, .hd720), (1, 720, .hd720), (1279, 719, .sd), (1, 0, .sd), (0, 1, .sd), (0, 0, nil), (-1, -1, nil)
        ]
        for (width, height, expected) in cases {
            #expect(MediaVideoQuality(.init(mediaStreams: [.init(height: height, type: .video, width: width)])).resolution == expected)
        }
    }

    @Test
    func `Dolby Vision takes priority over HDR fallback and missing dimensions remain absent`() {
        var stream = MediaStream(type: .video, videoRange: .hdr, videoRangeType: .doviWithSDR)
        var quality = MediaVideoQuality(.init(mediaStreams: [stream]))
        #expect(quality.resolution == nil && quality.range == .dolbyVision)
        stream.videoRangeType = .doviInvalid
        #expect(MediaVideoQuality(.init(mediaStreams: [stream])).range == .hdr)
        stream.videoRange = .sdr
        stream.videoRangeType = .hlg
        #expect(MediaVideoQuality(.init(mediaStreams: [stream])).range == .hdr)
        stream.videoRangeType = .unknown
        quality = MediaVideoQuality(.init(mediaStreams: [stream]))
        #expect(quality.resolution == nil && quality.range == nil)
    }

    @Test
    func `audio subtitle and unknown streams cannot supply video labels`() async {
        let item = BaseItemDto(
            mediaSources: [.init(mediaStreams: [.init(type: .subtitle, width: 7680)])],
            mediaStreams: [.init(isDefault: true, type: .audio, videoRange: .hdr, width: 3840), .init(width: 7680)]
        )
        let quality = await Task.detached { MediaVideoQuality(item) }.value
        #expect(quality.resolution == nil && quality.range == nil)
        #expect(MediaVideoQuality(BaseItemDto()).resolution == nil)
    }
}
