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
import SwiftfinUserMediaState
import Testing

private struct OriginalLibraryChange: Decodable { let itemID: String?
    let ticks: Int?
    let played: Bool?
    let loaded: Bool
}

private struct OriginalLibraryAction: Decodable { let kind: String
    let interval: Double?
    let removed: [String?]?
}

private struct OriginalLibraryArtwork: Decodable { let favorites: Bool
    let parentID: String?
    let live: Bool
}

private struct OriginalLibraryScope: Decodable { let parentID: String?
    let favorites: Bool
    let types: [String]
}

private struct OriginalLibraryFixture: Decodable {
    let originalCommit: String
    let sourceHashes: [String: String]
    let memberHashes: [String: String]
    let changes: [OriginalLibraryChange]
    let nextUp: [OriginalLibraryAction]
    let resume: [OriginalLibraryAction]
    let mediaTypes: [[MediaType]]
    let kinds: [[BaseItemKind]]
    let artwork: [OriginalLibraryArtwork]
    let artworkScopes: [OriginalLibraryScope]
    enum CodingKeys: String, CodingKey { case originalCommit, sourceHashes, memberHashes, changes, nextUp, resume, mediaTypes, kinds
        case artworkScopes = "artwork"
        case artworkInputs
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        originalCommit = try c.decode(String.self, forKey: .originalCommit)
        sourceHashes = try c.decode([String: String].self, forKey: .sourceHashes)
        memberHashes = try c.decode([String: String].self, forKey: .memberHashes)
        changes = try c.decode([OriginalLibraryChange].self, forKey: .changes)
        nextUp = try c.decode([OriginalLibraryAction].self, forKey: .nextUp)
        resume = try c.decode([OriginalLibraryAction].self, forKey: .resume)
        mediaTypes = try c.decode([[String]].self, forKey: .mediaTypes).map { $0.map { MediaType(rawValue: $0.capitalized)! } }
        kinds = try c.decode([[String]].self, forKey: .kinds)
            .map { $0.map { BaseItemKind(rawValue: $0.prefix(1).uppercased() + $0.dropFirst())! } }
        artworkScopes = try c.decode([OriginalLibraryScope].self, forKey: .artworkScopes)
        artwork = try c.decode([OriginalLibraryArtwork].self, forKey: .artworkInputs)
    }
}

struct LibraryOriginalContracts {
    private func fixture() throws -> OriginalLibraryFixture {
        let url = try #require(Bundle.module.url(forResource: "library-original-985add6d", withExtension: "json"))
        return try JSONDecoder().decode(OriginalLibraryFixture.self, from: Data(contentsOf: url))
    }

    @Test
    func `independent original library capture provenance`() throws {
        let original = try fixture()
        #expect(original.originalCommit == "985add6dca6e4733923857c8f0765cc77649691e")
        #expect(original.changes.count == 108 && original.mediaTypes.count == 156 && original.artwork.count == 12)
        #expect(original.sourceHashes == [
            "Packages/SwiftfinMediaCatalog/Sources/SwiftfinMediaCatalog/MediaCatalogPolicy.swift": "e7215c21a86322f75b846d9e03d494aec03b764bb824303754397d5a3af845b7",
            "Shared/Objects/Libraries/NextUpLibrary.swift": "34ae2e074ede1bbe68d2ac42b93e2ec7ea778aae3de3a24a91a2a75a9a86fa57",
            "Shared/Objects/Libraries/ResumeItemsLibrary.swift": "2f06888401d02af6ed2d611d12a92d09a15527758b20429f7af0bffd81286c28",
            "Shared/Objects/Libraries/UserViewLibrary.swift": "f3b860cc41baa55cc85e2dce4b834d9e2e955ec740eee411bf6476d0e06eece9"
        ])
        #expect(original.memberHashes == [
            "artworkScope": "a2c3f76e802c115cf2ff23df75017d05ed14fbf6af129356bc3bbd82fb33d33c",
            "mediaKinds": "a88b74bb9be55187ebd548420e6bdf00e706a964089be246e72aedd416ce7b8e",
            "nextUp": "f91331a51036808f5603cd33d3caec36f5c6f31bc7bee32c33b12e11350a43ca",
            "resume": "0ac46aef5df4ae3560a46a031885bad47201c84af15065812605cfb9894633e8"
        ])
    }

    @Test
    func `all original membership decisions preserve precedence and intervals`() throws {
        let f = try fixture()
        for (i, input) in f.changes.enumerated() {
            let dto = UserItemDataDto(isPlayed: input.played, itemID: input.itemID, key: "synthetic", playbackPositionTicks: input.ticks)
            for (actual, expected) in [
                (UserMediaStatePolicy.nextUpChange(for: dto, isLoaded: input.loaded), f.nextUp[i]),
                (UserMediaStatePolicy.resumeChange(for: dto, isLoaded: input.loaded), f.resume[i])
            ] {
                switch actual {
                case .none: #expect(expected.kind == "none")
                case let .refresh(interval): #expect(expected.kind == "refresh" && expected.interval == interval)
                case let .remove(itemID):
                    #expect(expected.kind == "remove" && itemID == input.itemID)
                    #expect(expected.removed == (input.loaded ? [input.itemID] : []))
                }
            }
        }
    }

    @Test
    func `all original ordered media type vectors match`() throws {
        let f = try fixture()
        for (input, expected) in zip(f.mediaTypes, f.kinds) {
            #expect(MediaCatalogPolicy.libraryItemTypes(for: input) == expected)
        }
    }

    @Test
    func `all original artwork scopes match without broadening library parents`() throws {
        let f = try fixture()
        for (input, expected) in zip(f.artwork, f.artworkScopes) {
            let scope: LibraryArtworkScope = input.favorites ? .favorites : .userView(.init(
                collectionType: input.live ? .livetv : .movies,
                id: input.parentID
            ))
            guard case let .artworkSample(parentID, types, favorites) = MediaCatalogPolicy.artworkQuery(for: scope)
            else { Issue.record("Unexpected query")
                continue
            }
            #expect(parentID == expected.parentID && favorites == expected.favorites)
            #expect(types.map { $0.rawValue.prefix(1).lowercased() + $0.rawValue.dropFirst() } == expected.types)
        }
    }
}
