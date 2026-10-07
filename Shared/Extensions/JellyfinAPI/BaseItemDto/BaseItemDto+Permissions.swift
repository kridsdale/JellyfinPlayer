//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import FactoryKit
import JellyfinAPI
import SwiftfinItemMetadata

@MainActor
extension BaseItemDto {

    /// Indicates whether the item can be downloaded by the current user
    var canBeDownloaded: Bool {
        ItemMetadataPolicy.permissions(for: self, policy: Container.shared.currentUserSession()?.user.data.policy).canDownload
    }

    /// Indicates whether the item's metadata can be edited by the current user
    var canEditMetadata: Bool {
        ItemMetadataPolicy.permissions(for: self, policy: Container.shared.currentUserSession()?.user.data.policy).canEditMetadata
    }

    /// Indicates whether the item's lyrics can be edited by the current user
    var canEditLyrics: Bool {
        ItemMetadataPolicy.permissions(for: self, policy: Container.shared.currentUserSession()?.user.data.policy).canEditLyrics
    }

    /// Indicates whether the item's subtitles can be edited by the current user
    var canEditSubtitles: Bool {
        ItemMetadataPolicy.permissions(for: self, policy: Container.shared.currentUserSession()?.user.data.policy).canEditSubtitles
    }
}
