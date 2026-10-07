//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation
import JellyfinAPI

public extension MediaStream {

    var is4kVideo: Bool {
        (width ?? 0) > 3800 && type == .video
    }

    var is51AudioChannelLayout: Bool {
        channelLayout == "5.1"
    }

    var is71AudioChannelLayout: Bool {
        channelLayout == "7.1"
    }

    var isHDVideo: Bool {
        (width ?? 0) > 1900 && type == .video
    }
}

public extension [MediaStream] {

    /// Text-based external subtitles loaded as sidecar files. Image-based subtitles are excluded because the player silently drops them.
    var sidecarSubtitles: [MediaStream] {
        filter { $0.deliveryMethod == .external && $0.deliveryURL != nil && $0.isTextSubtitleStream == true }
    }

    var has4KVideo: Bool {
        contains { $0.is4kVideo }
    }

    var has51AudioChannelLayout: Bool {
        contains { $0.is51AudioChannelLayout }
    }

    var has71AudioChannelLayout: Bool {
        contains { $0.is71AudioChannelLayout }
    }

    var hasHDVideo: Bool {
        contains { $0.isHDVideo }
    }

    var hasHDRVideo: Bool {
        contains { $0.videoRangeType?.isHDR == true }
    }

    var hasDolbyVision: Bool {
        contains { $0.videoRangeType?.isDolbyVision == true }
    }

    var hasSubtitles: Bool {
        contains { $0.type == .subtitle }
    }
}

public extension VideoRangeType {

    /// Returns `true` if the video format is HDR (including Dolby Vision).
    var isHDR: Bool {
        switch self {
        case .sdr, .doviInvalid, .unknown:
            false
        default:
            true
        }
    }

    /// Returns `true` if the video format is Dolby Vision.
    var isDolbyVision: Bool {
        switch self {
        case .dovi, .doviWithEL, .doviWithHLG, .doviWithSDR, .doviWithHDR10, .doviWithHDR10Plus, .doviWithELHDR10Plus:
            true
        default:
            false
        }
    }
}
