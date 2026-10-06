//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Defaults
import JellyfinAPI
import SwiftfinCollections
import SwiftfinLocalization
import SwiftfinPlaybackProfiles
import SwiftfinStoredValues

extension VideoPlayerType: Displayable {
    var displayTitle: String {
        switch self {
        case .native:
            L10n.native
        case .vlc:
            L10n.vlc
        case .mpv:
            L10n.mpv
        }
    }
}

extension VideoPlayerType: @retroactive SupportedCaseIterable {
    @ArrayBuilder<VideoPlayerType>
    public static var supportedCases: [VideoPlayerType] {
        VideoPlayerType.native
        VideoPlayerType.vlc
        if Defaults[.Experimental.mpvPlayer] {
            VideoPlayerType.mpv
        }
    }
}

extension VideoPlayerType {
    @MainActor
    var directPlayProfiles: [DirectPlayProfile] {
        directPlayProfiles(capabilities: PlaybackCapabilities.snapshot)
    }

    @MainActor
    var transcodingProfiles: [TranscodingProfile] {
        transcodingProfiles(capabilities: PlaybackCapabilities.snapshot)
    }
}
