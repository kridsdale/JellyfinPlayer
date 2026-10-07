//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import JellyfinAPI

/// Type eligibility for favorites and watched-state controls, without a session.
public struct UserMediaCapabilities: Sendable, Equatable {
    public let canBeFavorited: Bool
    public let canBePlayed: Bool
}

public extension UserMediaStatePolicy {
    static func capabilities(for kind: BaseItemKind?) -> UserMediaCapabilities {
        let favorite: Bool = switch kind {
        case .program, .liveTvProgram, .tvProgram: false
        default: true
        }
        let played: Bool = switch kind {
        case .audio, .audioBook, .book, .boxSet, .channelFolderItem, .collectionFolder, .episode, .manualPlaylistsFolder,
             .movie, .musicAlbum, .musicArtist, .musicVideo, .playlist, .playlistsFolder, .recording, .season,
             .series, .trailer, .video: true
        default: false
        }
        return .init(canBeFavorited: favorite, canBePlayed: played)
    }
}
