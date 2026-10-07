//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import JellyfinAPI
import SwiftfinLocalization
import SwiftfinMediaCatalog
import SwiftfinUserMediaState

struct ResumeItemsLibrary: BaseItemKindLibrary {

    let mediaTypes: [MediaType]
    let parent: TitledLibraryParent = .init(displayTitle: L10n.continue, id: "continue-watching")

    var libraryItemTypes: [BaseItemKind] {
        MediaCatalogPolicy.libraryItemTypes(for: mediaTypes)
    }

    init(mediaTypes: [MediaType] = [.video]) {
        self.mediaTypes = mediaTypes
    }

    func retrievePage(
        environment: Empty,
        pageState: LibraryPageState
    ) async throws -> [BaseItemDto] {
        try await pageState.readMedia(.resume(mediaTypes: mediaTypes)).items
    }

    func onItemUserDataChanged(
        viewModel: PagingLibraryViewModel<ResumeItemsLibrary>,
        userData: UserItemDataDto
    ) {
        let isLoaded = userData.itemID.map { id in viewModel.elements.contains { $0.id == id } } ?? false
        switch UserMediaStatePolicy.resumeChange(for: userData, isLoaded: isLoaded) {
        case .none:
            break
        case let .remove(itemID):
            viewModel.removeElements { $0.id == itemID }
        case let .refresh(minimumInterval):
            viewModel.scheduleRefreshForItemUserData(minimumInterval: minimumInterval)
        }
    }
}
