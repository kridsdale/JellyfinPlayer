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
import JellyfinAPI
import StatefulMacros
import SwiftfinAsyncStreams
import SwiftfinFilters
import SwiftfinMediaCatalog
import SwiftfinText
import SwiftUI

@MainActor
@Stateful
final class SearchViewModel: ViewModel {
    struct Request: Sendable {
        let filters: ItemFilterCollection
        let validate: AsyncOperationGate.Checkpoint
    }

    @CasePathable
    enum Action {
        case beginSearch(Request)
        case performSearch(Request)
        case performSuggestions(Request)
        var transition: Transition {
            switch self {
            case let .beginSearch(request):
                request.filters.hasQueryableFilters ? .to(.searching) : .to(.initial)
            case .performSearch:
                .to(.searching, then: .initial).onRepeat(.cancel)
            case .performSuggestions: .none
            }
        }
    }

    enum State { case error, initial, searching }
    @Published
    private(set) var suggestions: [BaseItemDto] = []
    let itemContentGroupViewModel: ContentGroupViewModel<SearchContentGroupProvider>
    private var catalog: MediaCatalogClient?
    private let searches = AsyncOperationGate()
    private let suggestionReads = AsyncOperationGate()

    var filterViewModel: FilterViewModel {
        itemContentGroupViewModel.provider.filterViewModel
    }

    var isEmpty: Bool {
        itemContentGroupViewModel.groups.isEmpty
    }

    var isNotEmpty: Bool {
        !isEmpty
    }

    var canSearch: Bool {
        filterViewModel.currentFilters.hasQueryableFilters
    }

    override init() {
        itemContentGroupViewModel = .init(provider: .init())
        super.init()
        catalog = try? requireMediaCatalog()
        observeFilters()
    }

    private func request(filters: ItemFilterCollection, gate: AsyncOperationGate) -> Request? {
        guard let catalog, !Task.isCancelled, (try? catalog.checkBinding()) != nil else { return nil }
        let checkpoint = gate.begin()
        return Request(filters: filters, validate: {
            try checkpoint()
            try catalog.checkBinding()
            try checkpoint()
        })
    }

    private func observeFilters() {
        filterViewModel.$currentFilters
            .map { [weak self] filters -> Request? in
                guard let self else { return nil }
                // Capture the emitted value before debounce and retire all old pages now.
                guard let request = self.request(filters: filters, gate: self.searches) else {
                    self.searches.cancel()
                    self.itemContentGroupViewModel.invalidateRefresh()
                    return nil
                }
                self.itemContentGroupViewModel.invalidateRefresh()
                guard (try? request.validate()) != nil else { return nil }
                self.beginSearch(request)
                return request
            }
            .debounce(for: 0.5, scheduler: RunLoop.main)
            .sink { [weak self] request in
                guard let request, request.filters.hasQueryableFilters, (try? request.validate()) != nil else { return }
                self?.performSearch(request)
            }
            .store(in: &cancellables)
    }

    func search(query: String) {
        filterViewModel.currentFilters.query = query.nilIfBlank
    }

    @Function(\Action.Cases.beginSearch)
    private func _beginSearch(_ request: Request) async throws {
        try request.validate()
        await cancel()
    }

    @Function(\Action.Cases.performSearch)
    private func _performSearch(_ request: Request) async throws {
        try request.validate()
        itemContentGroupViewModel.provider.environment.filters = request.filters
        try request.validate()
        await itemContentGroupViewModel.refreshForScope(validate: request.validate)
        try request.validate()
    }

    func getSuggestions() {
        if let request = request(filters: filterViewModel.currentFilters, gate: suggestionReads) {
            performSuggestions(request)
        }
    }

    @Function(\Action.Cases.performSuggestions)
    private func _performSuggestions(_ request: Request) async throws {
        guard let catalog else { throw CancellationError() }
        try request.validate()
        await filterViewModel.getQueryFilters()
        try request.validate()
        let result = try await catalog.suggestions(fields: PosterSubtitleField.itemFields)
        try request.validate()
        suggestions = result
    }
}
