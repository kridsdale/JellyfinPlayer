//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import JellyfinAPI

/// Quality of the default video stream, with ordered fallback across media sources.
/// Resolution and range are values; consumers supply localized display labels.
public struct MediaVideoQuality: Sendable, Equatable {
    public enum Resolution: String, Sendable {
        case sd = "SD"
        case hd720 = "720p"
        case hd1080 = "1080p"
        case hd1440 = "1440p"
        case uhd4K = "4K"
        case uhd8K = "8K"
    }

    public enum Range: Sendable, Equatable {
        case hdr
        case dolbyVision
    }

    public let resolution: Resolution?
    public let range: Range?

    public init(_ item: BaseItemDto) {
        let streams = (item.mediaStreams ?? []) + (item.mediaSources ?? []).flatMap { $0.mediaStreams ?? [] }
        let videos = streams.filter { $0.type == .video }
        guard let stream = videos.first(where: { $0.isDefault == true }) ?? videos.first else {
            resolution = nil
            range = nil
            return
        }
        let width = stream.width ?? 0
        let height = stream.height ?? 0
        if width >= 7680 || height >= 4320 {
            resolution = .uhd8K
        } else if width >= 3840 || height >= 2160 {
            resolution = .uhd4K
        } else if width >= 2560 || height >= 1440 {
            resolution = .hd1440
        } else if width >= 1920 || height >= 1080 {
            resolution = .hd1080
        } else if width >= 1280 || height >= 720 {
            resolution = .hd720
        } else if width > 0 || height > 0 {
            resolution = .sd
        } else {
            resolution = nil
        }

        if stream.videoRangeType?.isDolbyVision == true {
            range = .dolbyVision
        } else if stream.videoRangeType?.isHDR == true || stream.videoRange == .hdr {
            range = .hdr
        } else {
            range = nil
        }
    }
}
