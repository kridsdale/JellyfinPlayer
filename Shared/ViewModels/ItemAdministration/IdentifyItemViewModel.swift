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

    struct SearchRequest: Sendable {
        let query: SearchQuery
        let validate: AsyncOperationGate.Checkpoint
    }

    @CasePathable
    enum Action {
        case _actuallySearch(request: SearchRequest)
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
    private let searchRequests: AsyncOperationGate
    private let updateRequests = AsyncOperationGate()
    private var searchQuery: CurrentValueSubject<SearchRequest, Never>

    init(item: BaseItemDto) {
        self.item = item
        let requests = AsyncOperationGate()
        self.searchRequests = requests
        self.searchQuery = .init(.init(query: .init(), validate: requests.begin()))
        super.init()

        searchQuery
            .debounce(for: 0.5, scheduler: RunLoop.main)
            .sink { [weak self] request in
                self?._actuallySearch(request: request)
            }
            .store(in: &cancellables)
    }

    @Function(\Action.Cases.search)
    private func _search(_ query: SearchQuery) async throws {
        guard !Task.isCancelled else { return }
        // A duplicate intent must not retire the in-flight request that debounce
        // will keep. Changed queries carry a checkpoint through queued delivery.
        guard query != searchQuery.value.query else { return }
        updateRequests.cancel()
        searchQuery.send(.init(query: query, validate: searchRequests.begin()))

        await cancel()
    }

    @Function(\Action.Cases._actuallySearch)
    private func __actuallySearch(_ request: SearchRequest) async throws {
        do {
            try request.validate()
            guard let itemID = item.id, let itemType = item.type else {
                searchResults = []
                return
            }
            let metadata = try requireItemMetadata()
            let results = try await metadata.identityResults(itemID: itemID, itemType: itemType, query: request.query)
            try metadata.checkBinding()
            try request.validate()
            searchResults = results
        } catch is CancellationError {
            return
        }
    }

    @Function(\Action.Cases.update)
    private func _update(_ searchResult: RemoteSearchResult) async throws {
        do {
            try Task.checkCancellation()
            guard let itemID = item.id else { return }
            searchRequests.cancel()
            let validate = updateRequests.begin()
            let metadata = try requireItemMetadata()
            let updated = try await metadata.applyIdentityAndReload(itemID: itemID, result: searchResult, validate: validate)
            try metadata.checkBinding()
            try validate()
            Notifications[.itemMetadataDidChange].post(updated)
            // Notification subscribers can replace the operation synchronously.
            try metadata.checkBinding()
            try validate()
            events.send(.updated)
        } catch is CancellationError {
            return
        }
    }
}
