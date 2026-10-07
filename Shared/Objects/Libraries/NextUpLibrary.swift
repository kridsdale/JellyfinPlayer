//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Defaults
import Foundation
import JellyfinAPI
import SwiftfinLocalization
import SwiftfinMediaCatalog
import SwiftfinUserMediaState

struct NextUpLibrary: BaseItemKindLibrary {

    struct Environment: WithDefaultValue {
        var enableRewatching: Bool
        var maxNextUp: TimeInterval

        static let `default`: Self = .init(
            enableRewatching: Defaults[.Customization.Home.resumeNextUp],
            maxNextUp: Defaults[.Customization.Home.maxNextUp]
        )
    }

    let libraryItemTypes: [BaseItemKind] = [.episode]
    let parent: TitledLibraryParent = .init(displayTitle: L10n.nextUp, id: "next-up")

    func retrievePage(
        environment: Environment,
        pageState: LibraryPageState
    ) async throws -> [BaseItemDto] {
        try await pageState.readMedia(.nextUp(rewatching: environment.enableRewatching, maximumAge: environment.maxNextUp, now: .now)).items
    }

    func onItemUserDataChanged(
        viewModel: PagingLibraryViewModel<NextUpLibrary>,
        userData: UserItemDataDto
    ) {
        let isLoaded = userData.itemID.map { id in viewModel.elements.contains { $0.id == id } } ?? false
        switch UserMediaStatePolicy.nextUpChange(for: userData, isLoaded: isLoaded) {
        case .none:
            break
        case let .remove(itemID):
            viewModel.removeElements { $0.id == itemID }
        case let .refresh(minimumInterval):
            viewModel.scheduleRefreshForItemUserData(minimumInterval: minimumInterval)
        }
    }
}
