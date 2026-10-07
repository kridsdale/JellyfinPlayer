//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation
import JellyfinAPI

/// Primitive native-track projection; no native playback handle or backend import.
public struct CategorizedMediaTrack: Sendable, Equatable {
    public let index: Int
    public let type: MediaStreamType
    public let title: String?
    public let external: Bool
    public init(index: Int, type: MediaStreamType, title: String? = nil, external: Bool = false) {
        self.index = index
        self.type = type
        self.title = title
        self.external = external
    }
}

public extension MediaTrackIndexMap {
    /// mpv numbers tracks separately by category, while Jellyfin uses global indexes.
    static func categorized(
        mediaStreams: [MediaStream], tracks: [CategorizedMediaTrack],
        isTranscoding: Bool, selectedAudioStreamIndex: Int?
    ) -> MediaTrackIndexMap {
        var map = MediaTrackIndexMap()
        for type in [MediaStreamType.audio, .subtitle] {
            let streams = mediaStreams.filter { $0.type == type && $0.isExternal != true }
                .sorted { ($0.index ?? -1) < ($1.index ?? -1) }
            let internalTracks = tracks.filter { $0.type == type && !$0.external }
            if isTranscoding {
                if type == .audio, let index = selectedAudioStreamIndex, let track = internalTracks.first {
                    map.setPlayerIndex(
                        track.index,
                        for: index
                    )
                }
            } else {
                for (stream, track) in zip(streams, internalTracks) {
                    if let index = stream.index {
                        map.setPlayerIndex(track.index, for: index)
                    }
                }
            }
        }
        for stream in mediaStreams.sidecarSubtitles {
            if let index = stream.index,
               let track = tracks.first(where: { $0.type == .subtitle && $0.external && $0.title == "swiftfin-subtitle-\(index)" })
            {
                map.setPlayerIndex(track.index, for: index)
            }
        }
        return map
    }
}
