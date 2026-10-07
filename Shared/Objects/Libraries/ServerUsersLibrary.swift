//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import JellyfinAPI
import SwiftfinLocalization
import SwiftfinUserAdministration

struct ServerUsersLibrary: PagingLibrary {

    let hasNextPage = false

    let parent = TitledLibraryParent(displayTitle: L10n.users, id: "server-users")

    func retrievePage(
        environment: Empty,
        pageState: LibraryPageState
    ) async throws -> [UserDto] {
        guard pageState.pageOffset == 0 else { return [] }
        return try await pageState.userAdministration.users()
    }
}
