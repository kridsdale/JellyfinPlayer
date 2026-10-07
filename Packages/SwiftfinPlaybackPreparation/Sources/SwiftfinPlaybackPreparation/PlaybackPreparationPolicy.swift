//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation
import JellyfinAPI

public enum PlaybackPreparationError: Error, Sendable {
    case missingItemID
    case missingSource
    case missingPlaySession
    case invalidURL
    case itemIdentityChanged
}

public struct PreparedPlayback: Sendable {
    public let item: BaseItemDto
    public let source: MediaSourceInfo
    public let playSessionID: String
    public let url: URL
    public init(item: BaseItemDto, source: MediaSourceInfo, playSessionID: String, url: URL) {
        self.item = item
        self.source = source
        self.playSessionID = playSessionID
        self.url = url
    }
}

public enum PlaybackPreparationPolicy {
    public static func initialSource(in item: BaseItemDto, preferred: MediaSourceInfo?) throws -> MediaSourceInfo {
        guard item.id != nil else { throw PlaybackPreparationError.missingItemID }
        guard let source = preferred ?? item.mediaSources?.first else { throw PlaybackPreparationError.missingSource }
        return source
    }

    public static func resolveSource(in sources: [MediaSourceInfo]?, initial: MediaSourceInfo) throws -> MediaSourceInfo {
        guard let sources else { throw PlaybackPreparationError.missingSource }
        if let match = sources.first(where: { $0.eTag == initial.eTag }) {
            return match
        }
        if let open = sources.first(where: { source in
            guard let token = source.openToken, let id = source.id else { return false }
            return token.contains(id)
        }) {
            return open
        }
        if let id = initial.id, let match = sources.first(where: { $0.id == id }) {
            return match
        }
        guard let first = sources.first else { throw PlaybackPreparationError.missingSource }
        return first
    }

    public static func info(
        item: BaseItemDto,
        initial: MediaSourceInfo,
        userID: String,
        profile: DeviceProfile,
        maxBitrate: Int,
        audio: Int?,
        subtitle: Int?
    ) -> PlaybackInfoDto {
        var dto = PlaybackInfoDto()
        dto.isAutoOpenLiveStream = true
        dto.deviceProfile = profile
        dto.liveStreamID = initial.liveStreamID
        dto.maxStreamingBitrate = maxBitrate
        dto.userID = userID
        dto.audioStreamIndex = audio
        dto.subtitleStreamIndex = subtitle
        if item.channelType != .tv, initial.type != .placeholder {
            dto.mediaSourceID = initial.id
        }
        return dto
    }
}
