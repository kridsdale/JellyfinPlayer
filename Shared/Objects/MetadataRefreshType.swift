//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import SwiftfinItemMetadata
import SwiftfinLocalization

typealias MetadataRefreshType = MetadataRefreshSelection

extension MetadataRefreshSelection: Displayable {
    var displayTitle: String {
        switch self {
        case .scan:
            L10n.scanForNewAndUpdatedFiles
        case .missing:
            L10n.searchForMissingMetadata
        case .all:
            L10n.replaceAllMetadata
        }
    }
}
