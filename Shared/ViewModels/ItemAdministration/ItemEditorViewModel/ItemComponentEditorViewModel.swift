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
import SwiftfinCollections
import SwiftfinItemMetadata

@MainActor
@Stateful
class ItemComponentEditorViewModel<Editor: ItemComponentEditor>: ViewModel {

    typealias Element = Editor.Element

    struct SearchRequest: Sendable {
        let term: String
        let validate: AsyncOperationGate.Checkpoint
    }

    @CasePathable
    enum Action {
        case actuallySearch(SearchRequest)
        case add([Element])
        case remove([Element])
        case reorder([Element])
        case search(String)

        var transition: Transition {
            switch self {
            case .add, .remove, .reorder:
                .background(.updating)
            case .search:
                .to(.initial)
            case .actuallySearch:
                .background(.searching)
            }
        }
    }

    enum BackgroundState {
        case updating
        case searching
    }

    enum Event {
        case updated
    }

    enum State {
        case initial
        case error
    }

    @Published
    private(set) var item: BaseItemDto
    @Published
    private(set) var matches: [Element] = []

    let editor: Editor
    private let searchRequests: AsyncOperationGate
    private let updateRequests = AsyncOperationGate()
    private var searchQuery: CurrentValueSubject<SearchRequest, Never>

    init(editor: Editor, item: BaseItemDto) {
        self.editor = editor
        self.item = item
        let requests = AsyncOperationGate()
        self.searchRequests = requests
        self.searchQuery = .init(.init(term: "", validate: requests.begin()))

        super.init()

        searchQuery
            .debounce(for: 0.5, scheduler: RunLoop.main)
            .sink { [weak self] request in
                guard let self else { return }
                do {
                    try request.validate()
                    if request.term.isNotEmpty {
                        actuallySearch(request)
                    } else {
                        matches = []
                    }
                } catch is CancellationError {
                    return
                } catch {
                    return
                }
            }
            .store(in: &cancellables)
    }

    @Function(\Action.Cases.search)
    private func _search(_ searchTerm: String) async throws {
        guard !Task.isCancelled else { return }
        searchQuery.send(.init(term: searchTerm, validate: searchRequests.begin()))
        await cancel()
    }

    @Function(\Action.Cases.actuallySearch)
    private func _actuallySearch(_ request: SearchRequest) async throws {
        do {
            try request.validate()
            let metadata = try requireItemMetadata()
            let results = try await editor.search(request.term, metadata: metadata)
            try metadata.checkBinding()
            try request.validate()
            matches = results
        } catch is CancellationError {
            return
        }
    }

    @Function(\Action.Cases.add)
    private func _add(_ elements: [Element]) async throws {
        do {
            try await updateItem(editor.adding(elements, to: item)) { [editor] metadata in
                editor.didAdd(elements, metadata: metadata)
            }
        } catch is CancellationError {
            return
        }
    }

    @Function(\Action.Cases.remove)
    private func _remove(_ elements: [Element]) async throws {
        do {
            try await updateItem(editor.removing(elements, from: item))
        } catch is CancellationError {
            return
        }
    }

    @Function(\Action.Cases.reorder)
    private func _reorder(_ elements: [Element]) async throws {
        do {
            try await updateItem(editor.reordering(elements, in: item))
        } catch is CancellationError {
            return
        }
    }

    private func updateItem(
        _ newItem: BaseItemDto,
        didApply: (@MainActor (ItemMetadataClient) -> Void)? = nil
    ) async throws {
        try Task.checkCancellation()
        guard let itemID = item.id else { throw ErrorMessage("Item ID is missing") }
        searchRequests.cancel()
        let checkpoint = updateRequests.begin()
        let validate: AsyncOperationGate.Checkpoint = { [weak self] in
            try checkpoint()
            guard self?.item.id == itemID else { throw CancellationError() }
        }
        let metadata = try requireItemMetadata()
        let updated = try await metadata.updateAndReload(itemID: itemID, item: newItem, validate: validate)
        try metadata.checkBinding()
        try validate()
        item = updated
        try metadata.checkBinding()
        try validate()
        Notifications[.itemMetadataDidChange].post(updated)
        // Subscribers can synchronously replace the item or operation.
        try metadata.checkBinding()
        try validate()
        events.send(.updated)
        try metadata.checkBinding()
        try validate()
        didApply?(metadata)
    }
}
