//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation
import JellyfinAPI

public struct MetadataBindingID: Hashable, Sendable {
    public let transport: ObjectIdentifier
    public let userID: String
    public init(transport: ObjectIdentifier, userID: String) {
        self.transport = transport
        self.userID = userID
    }
}

public struct MetadataSearchQuery: Equatable, Sendable {
    public var name: String?
    public var originalTitle: String?
    public var year: Int?
    public init(name: String? = nil, originalTitle: String? = nil, year: Int? = nil) {
        self.name = name
        self.originalTitle = originalTitle
        self.year = year
    }

    public var isEmpty: Bool {
        name?.isEmpty != false && originalTitle?.isEmpty != false && year == nil
    }

    public var isNotEmpty: Bool {
        !isEmpty
    }
}

public struct MetadataRefreshOptions: Sendable {
    public let metadataMode: MetadataRefreshMode
    public let imageMode: MetadataRefreshMode
    public let replaceMetadata: Bool
    public let replaceImages: Bool
    public let regenerateTrickplay: Bool
    public init(
        metadataMode: MetadataRefreshMode,
        imageMode: MetadataRefreshMode,
        replaceMetadata: Bool,
        replaceImages: Bool,
        regenerateTrickplay: Bool
    ) {
        self.metadataMode = metadataMode
        self.imageMode = imageMode
        self.replaceMetadata = replaceMetadata
        self.replaceImages = replaceImages
        self.regenerateTrickplay = regenerateTrickplay
    }
}

public struct MetadataSubtitleDeletionFailure: Error {
    public let index: Int
    public let underlying: any Error
    public init(index: Int, underlying: any Error) {
        self.index = index
        self.underlying = underlying
    }
}

public enum MetadataComponentChange<Value: Equatable & Sendable>: Sendable { case append([Value]), remove([Value]), replace([Value]) }
public struct MetadataSubtitleGroups: Sendable {
    public let internalStreams: [MediaStream]
    public let externalStreams: [MediaStream]
}
