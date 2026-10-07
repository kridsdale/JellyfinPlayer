//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import JellyfinAPI
import SwiftfinItemMetadata

struct ItemComponentEditorInput {

    var id: String?
    var name: String
    var personKind: PersonKind
    var personRole: String
}

@MainActor
protocol ItemComponentEditor: Displayable, SendableMetatype {

    associatedtype Element: LibraryElement & Sendable

    var description: String { get }

    func adding(_ elements: [Element], to item: BaseItemDto) -> BaseItemDto
    func containsElement(named name: String, in item: BaseItemDto) -> Bool
    func elements(in item: BaseItemDto) -> [Element]
    func id(for element: Element) -> String?
    func makeElement(input: ItemComponentEditorInput) -> Element
    func matchExists(named name: String, in matches: [Element]) -> Bool
    func name(for element: Element) -> String
    func removing(_ elements: [Element], from item: BaseItemDto) -> BaseItemDto
    func reordering(_ elements: [Element], in item: BaseItemDto) -> BaseItemDto

    func didAdd(_ elements: [Element], metadata: ItemMetadataClient)
    func search(_ searchTerm: String, metadata: ItemMetadataClient) async throws -> [Element]
}

extension ItemComponentEditor {
    func containsElement(named name: String, in item: BaseItemDto) -> Bool {
        ItemMetadataPolicy.nameMatches(name, names: elements(in: item).map { self.name(for: $0) })
    }

    func matchExists(named name: String, in matches: [Element]) -> Bool {
        ItemMetadataPolicy.nameMatches(name, names: matches.map { self.name(for: $0) })
    }

    func id(for element: Element) -> String? {
        nil
    }

    func didAdd(_ elements: [Element], metadata: ItemMetadataClient) {}
}
