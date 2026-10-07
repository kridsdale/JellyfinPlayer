//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import JellyfinAPI
import SwiftfinCollections
import SwiftfinLocalization
import SwiftfinMediaCatalog
import SwiftfinStoredValues

extension BaseItemDto: LibraryParent {

    struct Grouping: Codable, Displayable, Hashable, Identifiable, Storable {

        let displayTitle: String
        let id: String

        static let episodes = Grouping(displayTitle: L10n.episodes, id: "episodes")
        static let seasons = Grouping(displayTitle: L10n.seasons, id: "seasons")
        static let series = Grouping(displayTitle: L10n.series, id: "series")
    }

    var libraryType: BaseItemKind? {
        type
    }

    var groupings: (defaultSelection: Grouping, elements: [Grouping])? {
        switch collectionType {
        case .tvshows:
            (.series, [.episodes, .seasons, .series])
        default:
            nil
        }
    }

    var supportedItemTypes: [BaseItemKind] {
        supportedItemTypes(for: nil)
    }

    func supportedItemTypes(for grouping: Grouping?) -> [BaseItemKind] {
        MediaCatalogPolicy.itemTypes(parentType: libraryType, collectionType: collectionType, groupingID: grouping?.id)
    }

    var isRecursiveCollection: Bool {
        isRecursiveCollection(for: nil)
    }

    func isRecursiveCollection(for grouping: Grouping?) -> Bool {
        MediaCatalogPolicy.isRecursive(parentType: libraryType, collectionType: collectionType, groupingID: grouping?.id)
    }
}
