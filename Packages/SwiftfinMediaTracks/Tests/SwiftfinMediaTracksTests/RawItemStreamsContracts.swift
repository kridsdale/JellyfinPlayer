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

struct RawItemStreamsContracts {
    @Test
    func `raw projection retains external dropped encoded duplicates and original order`() {
        let streams = [
            MediaStream(index: 9, isExternal: true, type: .audio),
            MediaStream(index: 9, type: .audio),
            MediaStream(deliveryMethod: .drop, index: 4, type: .subtitle),
            MediaStream(deliveryMethod: .encode, index: 1, isExternal: true, type: .subtitle),
            MediaStream(index: 0, type: .video),
            MediaStream(index: -1)
        ]
        #expect(MediaStreamKindPolicy.streams(in: streams, matching: .audio) == Array(streams.prefix(2)))
        #expect(MediaStreamKindPolicy.streams(in: streams, matching: .subtitle) == Array(streams[2 ... 3]))
        #expect(MediaStreamKindPolicy.streams(in: streams, matching: .video) == [streams[4]])
    }

    @Test
    func `absent empty and other stream kinds become empty raw kind lists`() {
        for kind in [MediaStreamType.audio, .subtitle, .video] {
            #expect(MediaStreamKindPolicy.streams(in: nil, matching: kind).isEmpty)
            #expect(MediaStreamKindPolicy.streams(in: [], matching: kind).isEmpty)
            #expect(MediaStreamKindPolicy.streams(in: [.init(type: .data)], matching: kind).isEmpty)
        }
    }
}
