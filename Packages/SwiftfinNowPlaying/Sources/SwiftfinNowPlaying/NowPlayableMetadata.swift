//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation
import MediaPlayer

@MainActor
public struct NowPlayableStaticMetadata {

    public let mediaType: MPNowPlayingInfoMediaType
    public let isLiveStream: Bool

    public let title: String
    public let artist: String?
    public let artwork: MPMediaItemArtwork?

    public let albumArtist: String?
    public let albumTitle: String?

    public init(
        mediaType: MPNowPlayingInfoMediaType,
        isLiveStream: Bool = false,
        title: String,
        artist: String? = nil,
        artwork: MPMediaItemArtwork? = nil,
        albumArtist: String? = nil,
        albumTitle: String? = nil
    ) {
        self.mediaType = mediaType
        self.isLiveStream = isLiveStream
        self.title = title
        self.artist = artist
        self.artwork = artwork
        self.albumArtist = albumArtist
        self.albumTitle = albumTitle
    }
}

@MainActor
public struct NowPlayableDynamicMetadata {

    public let rate: Float
    public let position: Duration
    public let duration: Duration

    public let currentLanguageOptions: [MPNowPlayingInfoLanguageOption]
    public let availableLanguageOptionGroups: [MPNowPlayingInfoLanguageOptionGroup]

    public init(
        rate: Float = 1,
        position: Duration,
        duration: Duration,
        currentLanguageOptions: [MPNowPlayingInfoLanguageOption] = [],
        availableLanguageOptionGroups: [MPNowPlayingInfoLanguageOptionGroup] = []
    ) {
        self.rate = rate
        self.position = position
        self.duration = duration
        self.currentLanguageOptions = currentLanguageOptions
        self.availableLanguageOptionGroups = availableLanguageOptionGroups
    }
}
