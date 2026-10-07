//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation
import JellyfinAPI
import SwiftfinCollections
import SwiftfinLocalization
import SwiftfinMediaCatalog
import SwiftUI

struct ScheduledRecordingsLibrary: BaseItemKindLibrary {

    let hasNextPage = false

    let libraryItemTypes: [BaseItemKind] = [.program]
    let parent: TitledLibraryParent = .init(
        displayTitle: L10n.schedule,
        id: "schedule"
    )

    func retrievePage(
        environment: Empty,
        pageState: LibraryPageState
    ) async throws -> [BaseItemDto] {
        try await pageState.readMedia(.scheduledRecordings).items
    }

    func makeLibraryBody(
        viewModel: PagingLibraryViewModel<Self>,
        @ViewBuilder content: @escaping () -> some View
    ) -> AnyView {
        content()
            .onReceive(Notifications[.recordingTimersDidChange].publisher) {
                viewModel.background.refresh()
            }
            .eraseToAnyView()
    }
}
