//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation
import JellyfinAPI
import SwiftfinMediaCatalog
import Testing

struct AppCatalogOriginalContracts {
    private struct Fixture: Decodable {
        struct Parent: Decodable { let kind: String?
            let itemTypes: [String]
        }

        struct Extra: Decodable { let type: String
            let isVideo: Bool
        }

        let libraryKinds: [Parent]
        let extras: [Extra]
    }

    private let original = #"""
    {
      "extras": [
        {
          "isVideo": true,
          "type": "Unknown"
        },
        {
          "isVideo": true,
          "type": "Clip"
        },
        {
          "isVideo": true,
          "type": "Trailer"
        },
        {
          "isVideo": true,
          "type": "BehindTheScenes"
        },
        {
          "isVideo": true,
          "type": "DeletedScene"
        },
        {
          "isVideo": true,
          "type": "Interview"
        },
        {
          "isVideo": true,
          "type": "Scene"
        },
        {
          "isVideo": true,
          "type": "Sample"
        },
        {
          "isVideo": false,
          "type": "ThemeSong"
        },
        {
          "isVideo": true,
          "type": "ThemeVideo"
        },
        {
          "isVideo": true,
          "type": "Featurette"
        },
        {
          "isVideo": true,
          "type": "Short"
        }
      ],
      "libraryKinds": [
        {
          "itemTypes": [
            "BoxSet",
            "Movie",
            "MusicVideo",
            "Series",
            "Video"
          ],
          "kind": null
        },
        {
          "itemTypes": [
            "BoxSet",
            "Movie",
            "MusicVideo",
            "Series",
            "Video"
          ],
          "kind": "AggregateFolder"
        },
        {
          "itemTypes": [
            "BoxSet",
            "Movie",
            "MusicVideo",
            "Series",
            "Video"
          ],
          "kind": "Audio"
        },
        {
          "itemTypes": [
            "BoxSet",
            "Movie",
            "MusicVideo",
            "Series",
            "Video"
          ],
          "kind": "AudioBook"
        },
        {
          "itemTypes": [
            "BoxSet",
            "Movie",
            "MusicVideo",
            "Series",
            "Video"
          ],
          "kind": "BasePluginFolder"
        },
        {
          "itemTypes": [
            "BoxSet",
            "Movie",
            "MusicVideo",
            "Series",
            "Video"
          ],
          "kind": "Book"
        },
        {
          "itemTypes": [
            "BoxSet",
            "Movie",
            "MusicVideo",
            "Series",
            "Video"
          ],
          "kind": "BoxSet"
        },
        {
          "itemTypes": [
            "BoxSet",
            "Movie",
            "MusicVideo",
            "Series",
            "Video"
          ],
          "kind": "Channel"
        },
        {
          "itemTypes": [
            "BoxSet",
            "Movie",
            "MusicVideo",
            "Series",
            "Video"
          ],
          "kind": "ChannelFolderItem"
        },
        {
          "itemTypes": [
            "BoxSet",
            "Movie",
            "MusicVideo",
            "Series",
            "Video"
          ],
          "kind": "CollectionFolder"
        },
        {
          "itemTypes": [
            "BoxSet",
            "Movie",
            "MusicVideo",
            "Series",
            "Video"
          ],
          "kind": "Episode"
        },
        {
          "itemTypes": [
            "BoxSet",
            "Movie",
            "MusicVideo",
            "Series",
            "Video",
            "Folder",
            "CollectionFolder"
          ],
          "kind": "Folder"
        },
        {
          "itemTypes": [
            "BoxSet",
            "Movie",
            "MusicVideo",
            "Series",
            "Video"
          ],
          "kind": "Genre"
        },
        {
          "itemTypes": [
            "BoxSet",
            "Movie",
            "MusicVideo",
            "Series",
            "Video"
          ],
          "kind": "ManualPlaylistsFolder"
        },
        {
          "itemTypes": [
            "BoxSet",
            "Movie",
            "MusicVideo",
            "Series",
            "Video"
          ],
          "kind": "Movie"
        },
        {
          "itemTypes": [
            "BoxSet",
            "Movie",
            "MusicVideo",
            "Series",
            "Video"
          ],
          "kind": "LiveTvChannel"
        },
        {
          "itemTypes": [
            "BoxSet",
            "Movie",
            "MusicVideo",
            "Series",
            "Video"
          ],
          "kind": "LiveTvProgram"
        },
        {
          "itemTypes": [
            "BoxSet",
            "Movie",
            "MusicVideo",
            "Series",
            "Video"
          ],
          "kind": "MusicAlbum"
        },
        {
          "itemTypes": [
            "BoxSet",
            "Movie",
            "MusicVideo",
            "Series",
            "Video"
          ],
          "kind": "MusicArtist"
        },
        {
          "itemTypes": [
            "BoxSet",
            "Movie",
            "MusicVideo",
            "Series",
            "Video"
          ],
          "kind": "MusicGenre"
        },
        {
          "itemTypes": [
            "BoxSet",
            "Movie",
            "MusicVideo",
            "Series",
            "Video"
          ],
          "kind": "MusicVideo"
        },
        {
          "itemTypes": [
            "BoxSet",
            "Movie",
            "MusicVideo",
            "Series",
            "Video"
          ],
          "kind": "Person"
        },
        {
          "itemTypes": [
            "BoxSet",
            "Movie",
            "MusicVideo",
            "Series",
            "Video"
          ],
          "kind": "Photo"
        },
        {
          "itemTypes": [
            "BoxSet",
            "Movie",
            "MusicVideo",
            "Series",
            "Video"
          ],
          "kind": "PhotoAlbum"
        },
        {
          "itemTypes": [
            "BoxSet",
            "Movie",
            "MusicVideo",
            "Series",
            "Video"
          ],
          "kind": "Playlist"
        },
        {
          "itemTypes": [
            "BoxSet",
            "Movie",
            "MusicVideo",
            "Series",
            "Video"
          ],
          "kind": "PlaylistsFolder"
        },
        {
          "itemTypes": [
            "BoxSet",
            "Movie",
            "MusicVideo",
            "Series",
            "Video"
          ],
          "kind": "Program"
        },
        {
          "itemTypes": [
            "BoxSet",
            "Movie",
            "MusicVideo",
            "Series",
            "Video"
          ],
          "kind": "Recording"
        },
        {
          "itemTypes": [
            "BoxSet",
            "Movie",
            "MusicVideo",
            "Series",
            "Video"
          ],
          "kind": "Season"
        },
        {
          "itemTypes": [
            "BoxSet",
            "Movie",
            "MusicVideo",
            "Series",
            "Video"
          ],
          "kind": "Series"
        },
        {
          "itemTypes": [
            "BoxSet",
            "Movie",
            "MusicVideo",
            "Series",
            "Video"
          ],
          "kind": "Studio"
        },
        {
          "itemTypes": [
            "BoxSet",
            "Movie",
            "MusicVideo",
            "Series",
            "Video"
          ],
          "kind": "Trailer"
        },
        {
          "itemTypes": [
            "BoxSet",
            "Movie",
            "MusicVideo",
            "Series",
            "Video"
          ],
          "kind": "TvChannel"
        },
        {
          "itemTypes": [
            "BoxSet",
            "Movie",
            "MusicVideo",
            "Series",
            "Video"
          ],
          "kind": "TvProgram"
        },
        {
          "itemTypes": [
            "BoxSet",
            "Movie",
            "MusicVideo",
            "Series",
            "Video"
          ],
          "kind": "UserRootFolder"
        },
        {
          "itemTypes": [
            "BoxSet",
            "Movie",
            "MusicVideo",
            "Series",
            "Video"
          ],
          "kind": "UserView"
        },
        {
          "itemTypes": [
            "BoxSet",
            "Movie",
            "MusicVideo",
            "Series",
            "Video"
          ],
          "kind": "Video"
        },
        {
          "itemTypes": [
            "BoxSet",
            "Movie",
            "MusicVideo",
            "Series",
            "Video"
          ],
          "kind": "Year"
        }
      ]
    }
    """#
    private func fixture() throws -> Fixture {
        try JSONDecoder().decode(Fixture.self, from: Data(original.utf8))
    }

    @Test
    func `nil and every generic parent retain original type order without DTO channel overrides`() throws {
        for row in try fixture().libraryKinds {
            let kind: BaseItemKind? = try row.kind.map { try #require(BaseItemKind(rawValue: $0)) }
            #expect(MediaCatalogPolicy.libraryParentItemTypes(for: kind).map(\.rawValue) == row.itemTypes)
        }
        #expect(MediaCatalogPolicy.libraryParentItemTypes(for: .channel) == MediaCatalogPolicy.defaultItemTypes)
        #expect(MediaCatalogPolicy.itemTypes(parentType: .channel, collectionType: nil, groupingID: nil) == [.liveTvProgram])
    }

    @Test
    func `every original extra kind preserves video eligibility`() throws {
        for row in try fixture().extras {
            let type = try #require(ExtraType(rawValue: row.type))
            #expect(MediaCatalogPolicy.isVideoExtra(type) == row.isVideo)
        }
    }
}
