//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation
import JellyfinAPI
import SwiftfinLocalization
import SwiftfinServerOperations

struct ServerActivityLibrary: PagingLibrary {

    struct Environment: WithDefaultValue {
        var hasUserID: Bool?
        var minDate: Date?

        static var `default`: Self {
            .init()
        }
    }

    let parent = TitledLibraryParent(displayTitle: L10n.activity, id: "server-activity")

    func retrievePage(
        environment: Environment,
        pageState: LibraryPageState
    ) async throws -> [ActivityLogEntry] {
        try await pageState.serverOperations.activity(
            offset: pageState.pageOffset,
            limit: pageState.pageSize,
            hasUserID: environment.hasUserID,
            minimumDate: environment.minDate
        )
    }
}
