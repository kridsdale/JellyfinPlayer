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
import SwiftfinItemMetadata
import SwiftfinLocalization
import SwiftfinUIState

@MainActor
@Stateful
class ItemEditorViewModel: ViewModel {
    @CasePathable
    enum Action {
        case performDelete(Request)
        case performRead(Request, Bool)
        case performRefresh(Request, MetadataRefreshOptions)
        case performUpdate(Request, BaseItemDto)
        var transition: Transition {
            .background(.updating)
        }
    }

    enum BackgroundState { case updating }
    enum Event { case deleted, metadataRefreshStarted, updated }
    enum State { case initial, error }
    @CommittedPublished
    var item: BaseItemDto {
        didSet { objectWillChange.send() }
    }

    struct Request: Sendable { let validate: AsyncOperationGate.Checkpoint }
    private let editor: ItemMetadataEditor?
    private let operations = AsyncOperationGate()

    private func request(using gate: AsyncOperationGate? = nil) -> Request? {
        guard let editor, item.id == editor.itemID, !Task.isCancelled,
              (try? editor.checkBinding()) != nil else { return nil }
        let check = (gate ?? operations).begin()
        return Request(validate: { [weak self] in
            try check()
            try editor.checkBinding()
            guard self?.item.id == editor.itemID else { throw CancellationError() }
            try check()
        })
    }

    init(item: BaseItemDto) {
        self.item = item
        editor = try? Container.shared.currentUserSession()?.itemMetadata.makeEditor(itemID: item.id ?? "")
        super.init()
    }

    func delete() {
        if let request = request() {
            performDelete(request)
        }
    }

    func refreshItem(sendNotification: Bool) {
        if let request = request() {
            performRead(request, sendNotification)
        }
    }

    func update(_ item: BaseItemDto) {
        if let request = request() {
            performUpdate(request, item)
        }
    }

    func refreshMetadata(
        metadataRefreshMode: MetadataRefreshMode,
        imageRefreshMode: MetadataRefreshMode,
        replaceMetadata: Bool,
        replaceImages: Bool,
        regenerateTrickplay: Bool
    ) {
        guard let request = request() else { return }
        performRefresh(request, .init(
            metadataMode: metadataRefreshMode,
            imageMode: imageRefreshMode,
            replaceMetadata: replaceMetadata,
            replaceImages: replaceImages,
            regenerateTrickplay: regenerateTrickplay
        ))
    }

    private func publish(_ updated: BaseItemDto, request: Request, notify: Bool = true) throws {
        try request.validate()
        item = updated
        try request.validate()
        if notify {
            Notifications[.itemMetadataDidChange].post(updated)
        }
        try request.validate()
        events.send(.updated)
    }

    @Function(\Action.Cases.performDelete)
    private func _performDelete(_ request: Request) async throws {
        guard let editor else { throw CancellationError() }
        try await editor.deleteItem(validate: request.validate)
        try request.validate()
        Notifications[.didDeleteItem].post(editor.itemID)
        try request.validate()
        events.send(.deleted)
    }

    @Function(\Action.Cases.performRead)
    private func _performRead(_ request: Request, _ notify: Bool) async throws {
        guard let editor else { throw CancellationError() }
        try await publish(editor.item(validate: request.validate), request: request, notify: notify)
    }

    @Function(\Action.Cases.performRefresh)
    private func _performRefresh(_ request: Request, _ options: MetadataRefreshOptions) async throws {
        guard let editor else { throw CancellationError() }
        let updated = try await editor.refresh(options: options, validate: request.validate, started: { [weak self] in
            guard let self, (try? request.validate()) != nil else { return }
            events.send(.metadataRefreshStarted)
        })
        try publish(updated, request: request)
    }

    @Function(\Action.Cases.performUpdate)
    private func _performUpdate(_ request: Request, _ item: BaseItemDto) async throws {
        guard let editor else { throw CancellationError() }
        try await publish(editor.update(item, validate: request.validate), request: request)
    }

    // Existing awaited callers retain the same fixed editor and admitted receipt.
    func updateItem(_ item: BaseItemDto) async throws {
        guard let request = request(), let editor else { throw CancellationError() }
        try await publish(editor.update(item, validate: request.validate), request: request)
    }
}
