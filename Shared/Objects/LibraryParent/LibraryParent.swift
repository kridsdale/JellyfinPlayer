//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import JellyfinAPI
import SwiftfinMediaCatalog

protocol LibraryParent: Displayable, Hashable, Identifiable<String?> {

    /// The type of the library, reusing `BaseItemKind` for some
    /// ease of provided variety like `folder` and `userView`.
    var libraryType: BaseItemKind? { get }

    /// The `BaseItemKind` types that this library parent
    /// support. Mainly used for `.folder` support.
    ///
    /// When using filters, this is used to determine the initial
    /// set of supported types and then
    var supportedItemTypes: [BaseItemKind] { get }
}

extension LibraryParent {

    var supportedItemTypes: [BaseItemKind] {
        MediaCatalogPolicy.libraryParentItemTypes(for: libraryType)
    }

    var pagingLibraryID: String {
        id ?? displayTitle
    }
}
