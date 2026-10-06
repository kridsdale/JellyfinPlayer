//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import JellyfinAPI

public extension VideoPlayerType {
    func directPlayProfiles(capabilities: PlaybackCapabilitySnapshot) -> [DirectPlayProfile] {
        switch self {
        case .native: NativeProfiles(capabilities: capabilities).directPlayProfiles
        case .vlc, .mpv: VLCProfiles(capabilities: capabilities).directPlayProfiles
        }
    }

    func transcodingProfiles(capabilities: PlaybackCapabilitySnapshot) -> [TranscodingProfile] {
        switch self {
        case .native: NativeProfiles(capabilities: capabilities).transcodingProfiles
        case .vlc, .mpv: VLCProfiles(capabilities: capabilities).transcodingProfiles
        }
    }

    var subtitleProfiles: [SubtitleProfile] {
        switch self {
        case .native: NativeProfiles.subtitleProfiles
        case .vlc, .mpv: VLCProfiles.subtitleProfiles
        }
    }

    func codecProfiles(capabilities: PlaybackCapabilitySnapshot) -> [CodecProfile] {
        switch self {
        case .native: NativeProfiles(capabilities: capabilities).codecProfiles
        case .vlc, .mpv: VLCProfiles(capabilities: capabilities).codecProfiles
        }
    }
}
