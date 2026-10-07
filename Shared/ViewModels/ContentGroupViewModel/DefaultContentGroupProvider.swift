//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Defaults
import FactoryKit
import Foundation
import JellyfinAPI
import SwiftfinCollections
import SwiftfinLocalization

struct DefaultContentGroupProvider: ContentGroupProvider {

    @Injected(\.currentUserSession)
    var userSession: UserSession?

    let displayTitle: String = L10n.home
    let id: String = "default-content-group-provider"

    func makeGroups(environment: Empty) async throws -> [any ContentGroup] {
        guard let userSession else { return [] }
        let catalog = userSession.mediaCatalog
        let excludedIDs = userSession.user.data.configuration?.latestItemsExcludes ?? []
        let views = try await catalog.homeViews(excludedIDs: excludedIDs)
        try catalog.checkBinding()
        return _makeGroups(userViews: views)
    }

    @ContentGroupBuilder
    private func _makeGroups(userViews: [BaseItemDto]) -> [any ContentGroup] {

        #if os(tvOS)
        let cinematicSelectionContentGroup = CinematicSelectionContentGroup(
            resumeLibrary: ResumeItemsLibrary(mediaTypes: [.video]),
            recentlyAddedLibrary: RecentlyAddedLibrary()
        )

        cinematicSelectionContentGroup
        #else
        PosterGroup(
            library: ResumeItemsLibrary(mediaTypes: [.video]),
            posterDisplayType: .landscape,
            posterSize: .medium,
            _viewContext: .isInResume
        )
        #endif

        PosterGroup(
            library: NextUpLibrary()
        )

        if Defaults[.Customization.Home.showRecentlyAdded] {
            #if os(tvOS)
            CinematicRecentlyAddedContentGroup(
                viewModel: cinematicSelectionContentGroup.viewModel
            )
            #else
            PosterGroup(
                library: ItemLibrary(
                    parent: BaseItemDto(name: L10n.recentlyAdded.localizedCapitalized),
                    filters: .init(
                        itemTypes: [.movie, .series],
                        sortBy: [.dateCreated],
                        sortOrder: [.descending]
                    )
                )
            )
            #endif
        }

        if Defaults[.Customization.Home.showRecentlyPlayed] {
            PosterGroup(
                library: ItemLibrary(
                    parent: BaseItemDto(name: L10n.recentlyPlayed.localizedCapitalized),
                    filters: .init(
                        itemTypes: [.movie, .series],
                        sortBy: [.datePlayed],
                        sortOrder: [.descending],
                        traits: [.isPlayed]
                    )
                )
            )
        }

        PosterGroup(
            id: "programs-recommended",
            library: RecommendedProgramsLibrary(),
            posterDisplayType: .landscape,
            posterSize: .small
        )

        userViews
            .map(LatestInLibrary.init)
            .map {
                PosterGroup(
                    library: $0,
                    posterDisplayType: .landscape
                )
            }
    }
}
