//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Combine
import Foundation
import JellyfinAPI
import OrderedCollections
import SwiftfinItemMetadata

@MainActor
@Stateful
class ItemEditorViewModel: ViewModel {

    @CasePathable
    enum Action {

        /// Generic Actions
        case delete
        case refreshItem(sendNotification: Bool)
        case refreshMetadata(
            metadataRefreshMode: MetadataRefreshMode,
            imageRefreshMode: MetadataRefreshMode,
            replaceMetadata: Bool,
            replaceImages: Bool,
            regenerateTrickplay: Bool
        )
        case update(BaseItemDto)

        var transition: Transition {
            switch self {
            case .delete, .update, .refreshItem, .refreshMetadata:
                .background(.updating)
            }
        }
    }

    enum BackgroundState {
        case updating
    }

    enum Event {
        case deleted
        case metadataRefreshStarted
        case updated
    }

    enum State {
        case initial
        case error
    }

    // MARK: - Published Properties

    @Published
    var item: BaseItemDto

    // MARK: - Initialization

    init(item: BaseItemDto) {
        self.item = item
        super.init()
    }

    // MARK: - Actions

    @Function(\Action.Cases.delete)
    private func _delete() async throws {
        guard let itemID = item.id else { return }
        try await requireItemMetadata().deleteItem(id: itemID)
        Notifications[.didDeleteItem].post(itemID)
        events.send(.deleted)
    }

    @Function(\Action.Cases.refreshMetadata)
    private func _refreshMetadata(
        _ metadataRefreshMode: MetadataRefreshMode,
        _ imageRefreshMode: MetadataRefreshMode,
        _ replaceMetadata: Bool,
        _ replaceImages: Bool,
        _ regenerateTrickplay: Bool
    ) async throws {
        guard let itemID = item.id else { return }
        let metadata = try requireItemMetadata()
        try await metadata.refresh(
            itemID: itemID,
            options: .init(
                metadataMode: metadataRefreshMode,
                imageMode: imageRefreshMode,
                replaceMetadata: replaceMetadata,
                replaceImages: replaceImages,
                regenerateTrickplay: regenerateTrickplay
            )
        )
        events.send(.metadataRefreshStarted)
        try await Task.sleep(for: .seconds(5))
        try metadata.checkBinding()
        guard item.id == itemID else { throw CancellationError() }
        let updated = try await metadata.item(id: itemID)
        guard item.id == itemID else { throw CancellationError() }
        item = updated
        Notifications[.itemMetadataDidChange].post(updated)
        events.send(.updated)
    }

    @Function(\Action.Cases.update)
    private func _update(_ newItem: BaseItemDto) async throws {
        try await updateItem(newItem)
    }

    @Function(\Action.Cases.refreshItem)
    private func _refreshItem(_ isRefresh: Bool) async throws {
        guard let itemID = item.id else { throw ErrorMessage("Item ID is missing") }
        let updated = try await requireItemMetadata().item(id: itemID)
        guard item.id == itemID else { throw CancellationError() }
        item = updated
        if isRefresh {
            Notifications[.itemMetadataDidChange].post(updated)
        }
        events.send(.updated)
    }

    // MARK: - Update Item

    // TODO: call update(_:) instead

    func updateItem(_ newItem: BaseItemDto) async throws {
        guard let itemID = item.id else { return }
        let metadata = try requireItemMetadata()
        try await metadata.update(itemID: itemID, item: newItem)
        let updated = try await metadata.item(id: itemID)
        guard item.id == itemID else { throw CancellationError() }
        item = updated
        Notifications[.itemMetadataDidChange].post(updated)
        events.send(.updated)
    }
}
