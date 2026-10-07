//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import JellyfinAPI
import SwiftfinItemMetadata
import SwiftfinLocalization

struct GenreComponentEditor: ItemComponentEditor {

    let description: String = L10n.genresDescription
    let displayTitle: String = L10n.genres

    func elements(in item: BaseItemDto) -> [String] {
        item.genres ?? []
    }

    func name(for element: String) -> String {
        element
    }

    func makeElement(input: ItemComponentEditorInput) -> String {
        input.name
    }

    func adding(_ genres: [String], to item: BaseItemDto) -> BaseItemDto {
        ItemMetadataPolicy.genres(.append(genres), in: item)
    }

    func removing(_ genres: [String], from item: BaseItemDto) -> BaseItemDto {
        ItemMetadataPolicy.genres(.remove(genres), in: item)
    }

    func reordering(_ genres: [String], in item: BaseItemDto) -> BaseItemDto {
        ItemMetadataPolicy.genres(.replace(genres), in: item)
    }

    func search(_ searchTerm: String, metadata: ItemMetadataClient) async throws -> [String] {
        try await metadata.genreMatches(query: searchTerm)
    }
}
