//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import JellyfinAPI
import SwiftfinItemMetadata

struct RemoteImageLibrary: PagingLibrary {

    struct Environment: Equatable, WithDefaultValue {
        var includeAllLanguages: Bool = false
        var provider: String?

        static var `default`: Self {
            .init()
        }
    }

    let imageType: ImageType
    let parent: TitledLibraryParent

    init(imageType: ImageType, itemID: String) {
        self.imageType = imageType
        self.parent = .init(displayTitle: imageType.displayTitle, id: itemID)
    }

    func retrievePage(
        environment: Environment,
        pageState: LibraryPageState
    ) async throws -> [RemoteImageInfo] {
        guard let itemID = parent.id else { return [] }
        return try await pageState.itemMetadata.remoteImages(
            itemID: itemID,
            type: imageType,
            includeAllLanguages: environment.includeAllLanguages,
            provider: environment.provider,
            offset: pageState.pageOffset,
            limit: pageState.pageSize
        )
    }
}
