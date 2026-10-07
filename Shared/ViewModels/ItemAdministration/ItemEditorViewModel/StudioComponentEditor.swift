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

struct StudioComponentEditor: ItemComponentEditor {

    let description: String = L10n.studiosDescription
    let displayTitle: String = L10n.studios

    func elements(in item: BaseItemDto) -> [NameIDPair] {
        item.studios ?? []
    }

    func id(for element: NameIDPair) -> String? {
        element.id
    }

    func name(for element: NameIDPair) -> String {
        element.name ?? L10n.unknown
    }

    func makeElement(input: ItemComponentEditorInput) -> NameIDPair {
        NameIDPair(id: input.id, name: input.name)
    }

    func adding(_ studios: [NameIDPair], to item: BaseItemDto) -> BaseItemDto {
        ItemMetadataPolicy.studios(.append(studios), in: item)
    }

    func removing(_ studios: [NameIDPair], from item: BaseItemDto) -> BaseItemDto {
        ItemMetadataPolicy.studios(.remove(studios), in: item)
    }

    func reordering(_ studios: [NameIDPair], in item: BaseItemDto) -> BaseItemDto {
        ItemMetadataPolicy.studios(.replace(studios), in: item)
    }

    func search(_ searchTerm: String, metadata: ItemMetadataClient) async throws -> [NameIDPair] {
        try await metadata.studioMatches(query: searchTerm)
    }
}
