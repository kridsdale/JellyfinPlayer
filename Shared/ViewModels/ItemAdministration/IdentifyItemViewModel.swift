//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import CasePaths
import Combine
import Foundation
import Get
import JellyfinAPI
import OrderedCollections
import StatefulMacros
import SwiftfinAsyncStreams
import SwiftfinCollections
import SwiftfinItemMetadata

@MainActor
@Stateful
final class IdentifyItemViewModel: ViewModel {

    typealias SearchQuery = MetadataSearchQuery

    @CasePathable
    enum Action {
        case _actuallySearch(query: SearchQuery)
        case search(query: SearchQuery)
        case update(RemoteSearchResult)

        var transition: Transition {
            switch self {
            case ._actuallySearch, .search:
                .background(.searching)
            case .update:
                .background(.updating)
            }
        }
    }

    enum BackgroundState {
        case searching
        case updating
    }

    enum Event {
        case updated
    }

    enum State {
        case initial
        case error
    }

    @Published
    private(set) var searchResults: [RemoteSearchResult] = []

    let item: BaseItemDto
    private var searchQuery = CurrentValueSubject<SearchQuery, Never>(.init())

    init(item: BaseItemDto) {
        self.item = item
        super.init()

        searchQuery
            .debounce(for: 0.5, scheduler: RunLoop.main)
            .removeDuplicates()
            .sink { [weak self] query in
                self?._actuallySearch(query: query)
            }
            .store(in: &cancellables)
    }

    @Function(\Action.Cases.search)
    private func _search(_ query: SearchQuery) async throws {
        searchQuery.send(query)

        await cancel()
    }

    @Function(\Action.Cases._actuallySearch)
    private func __actuallySearch(_ query: SearchQuery) async throws {
        guard let itemID = item.id, let itemType = item.type else { searchResults = []
            return
        }
        searchResults = try await requireItemMetadata().identityResults(itemID: itemID, itemType: itemType, query: query)
    }

    @Function(\Action.Cases.update)
    private func _update(_ searchResult: RemoteSearchResult) async throws {
        guard let itemID = item.id else { return }
        let metadata = try requireItemMetadata()
        try await metadata.applyIdentity(itemID: itemID, result: searchResult)
        let updated = try await metadata.item(id: itemID)
        Notifications[.itemMetadataDidChange].post(updated)
        events.send(.updated)
    }
}
