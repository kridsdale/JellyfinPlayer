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

struct PeopleLibrary: BaseItemKindLibrary {

    struct Environment: WithDefaultValue {
        var query: String?

        static var `default`: Self {
            .init()
        }
    }

    let environment: Environment?
    let libraryItemTypes: [BaseItemKind] = [.person]
    let parent: TitledLibraryParent = .init(displayTitle: L10n.people, id: "people")

    init(environment: Environment = .default) {
        self.environment = environment
    }

    func retrievePage(
        environment: Environment,
        pageState: LibraryPageState
    ) async throws -> [BaseItemDto] {
        try await pageState.readMedia(.people(query: environment.query)).items
    }
}
