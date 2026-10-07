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

struct PeopleComponentEditor: ItemComponentEditor {

    let description: String = L10n.peopleDescription
    let displayTitle: String = L10n.people

    func elements(in item: BaseItemDto) -> [BaseItemPerson] {
        item.people ?? []
    }

    func id(for element: BaseItemPerson) -> String? {
        element.id
    }

    func name(for element: BaseItemPerson) -> String {
        element.name ?? L10n.unknown
    }

    func makeElement(input: ItemComponentEditorInput) -> BaseItemPerson {
        ItemMetadataPolicy.person(id: input.id, name: input.name, kind: input.personKind, role: input.personRole)
    }

    func adding(_ people: [BaseItemPerson], to item: BaseItemDto) -> BaseItemDto {
        ItemMetadataPolicy.people(.append(people), in: item)
    }

    func removing(_ people: [BaseItemPerson], from item: BaseItemDto) -> BaseItemDto {
        ItemMetadataPolicy.people(.remove(people), in: item)
    }

    func reordering(_ people: [BaseItemPerson], in item: BaseItemDto) -> BaseItemDto {
        ItemMetadataPolicy.people(.replace(people), in: item)
    }

    func search(_ searchTerm: String, metadata: ItemMetadataClient) async throws -> [BaseItemPerson] {
        try await metadata.peopleMatches(query: searchTerm)
    }
}
