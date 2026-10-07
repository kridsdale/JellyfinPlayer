//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import JellyfinAPI
import SwiftfinCollections
import SwiftfinItemMetadata
import SwiftfinLocalization

@MainActor
struct TagComponentEditor: ItemComponentEditor {

    let description: String = L10n.tagsDescription
    let displayTitle: String = L10n.tags

    private let tags = MetadataTagSearchStore()

    func elements(in item: BaseItemDto) -> [String] {
        item.tags ?? []
    }

    func name(for element: String) -> String {
        element
    }

    func makeElement(input: ItemComponentEditorInput) -> String {
        input.name
    }

    func adding(_ tags: [String], to item: BaseItemDto) -> BaseItemDto {
        ItemMetadataPolicy.tags(.append(tags), in: item)
    }

    func removing(_ tags: [String], from item: BaseItemDto) -> BaseItemDto {
        ItemMetadataPolicy.tags(.remove(tags), in: item)
    }

    func reordering(_ tags: [String], in item: BaseItemDto) -> BaseItemDto {
        ItemMetadataPolicy.tags(.replace(tags), in: item)
    }

    func didAdd(_ tags: [String], metadata: ItemMetadataClient) {
        try? self.tags.add(tags, client: metadata)
    }

    func search(_ searchTerm: String, metadata: ItemMetadataClient) async throws -> [String] {
        try await tags.search(prefix: searchTerm, client: metadata)
    }
}
