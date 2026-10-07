//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation
import JellyfinAPI
import SwiftfinItemMetadata
import SwiftfinText

extension BaseItemPerson: Displayable {

    var displayTitle: String {
        name ?? .emptyDash
    }
}

extension BaseItemPerson: LibraryParent {

    var libraryType: BaseItemKind? {
        .person
    }
}

extension BaseItemPerson {

    var isCrew: Bool {
        ItemMetadataPolicy.isCrew(self)
    }

    /// Shows crew jobs, or first role in a multi-role string
    var displayRole: String? {
        ItemMetadataPolicy.displayRole(for: self)
    }
}
