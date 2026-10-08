//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import CasePaths
import Combine
import FactoryKit
import Foundation
import JellyfinAPI
import StatefulMacros
import SwiftfinAsyncStreams
import SwiftfinCollections
import SwiftfinItemMetadata
import SwiftfinUIState

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

    @CommittedPublished
    private(set) var item: BaseItemDto {
        didSet { objectWillChange.send() }
    }

    @CommittedPublished
    private(set) var matches: [Element] = [] {
        didSet { objectWillChange.send() }
    }

    let editor: Editor
    private let boundMetadata: ItemMetadataClient?
    private let boundItemEditor: ItemMetadataEditor?
    private let searchRequests: AsyncOperationGate
    private let updateRequests = AsyncOperationGate()
    private var searchQuery: CurrentValueSubject<SearchRequest, Never>

    init(editor: Editor, item: BaseItemDto) {
        self.editor = editor
        self.item = item
        let metadata = Container.shared.currentUserSession()?.itemMetadata
        self.boundMetadata = metadata
        self.boundItemEditor = try? metadata?.makeEditor(itemID: item.id ?? "")
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
                    try metadataClient().checkBinding()
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
        try metadataClient().checkBinding()
        searchQuery.send(.init(term: searchTerm, validate: searchRequests.begin()))
        await cancel()
    }

    @Function(\Action.Cases.actuallySearch)
    private func _actuallySearch(_ request: SearchRequest) async throws {
        do {
            try request.validate()
            let metadata = try metadataClient()
            let results = try await editor.search(request.term, metadata: metadata)
            try metadata.checkBinding()
            try request.validate()
            matches = results
        } catch {
            try metadataClient().checkBinding()
            try request.validate()
            if error is CancellationError {
                return
            }
            throw error
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
        let metadata = try metadataClient()
        guard let boundItemEditor, boundItemEditor.itemID == itemID else { throw CancellationError() }
        let updated = try await boundItemEditor.update(newItem, validate: validate)
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

    private func metadataClient() throws -> ItemMetadataClient {
        guard let boundMetadata, let boundItemEditor, item.id == boundItemEditor.itemID else { throw CancellationError() }
        try boundMetadata.checkBinding()
        return boundMetadata
    }
}
