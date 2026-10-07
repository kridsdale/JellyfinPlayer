//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import JellyfinAPI

/// The selected library, distinct from the user/transport binding owned by the client.
public enum LibraryArtworkScope: Sendable {
    case favorites
    case userView(BaseItemDto)
}

public extension MediaCatalogPolicy {
    /// Preserve input order and duplicates; unknown media contributes no item kinds.
    static func libraryItemTypes(for mediaTypes: [MediaType]) -> [BaseItemKind] {
        mediaTypes.flatMap { type -> [BaseItemKind] in
            switch type {
            case .audio: [.audio, .musicAlbum]
            case .video: [.episode, .movie, .video]
            case .book: [.book]
            case .photo: [.photo]
            case .unknown: []
            }
        }
    }

    static func artworkQuery(for scope: LibraryArtworkScope) -> MediaCatalogQuery {
        switch scope {
        case .favorites:
            .artworkSample(parentID: nil, itemTypes: defaultItemTypes, favorites: true)
        case let .userView(item):
            .artworkSample(
                parentID: item.collectionType == .livetv ? nil : item.id,
                itemTypes: item.collectionType == .livetv ? [.tvProgram, .liveTvProgram] : defaultItemTypes,
                favorites: false
            )
        }
    }
}
