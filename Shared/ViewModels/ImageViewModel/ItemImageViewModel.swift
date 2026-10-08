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
import UIKit

@MainActor
@Stateful
final class ItemImageViewModel: ViewModel {
    @CasePathable
    enum Action {
        case performRefresh(Request)
        case performDelete(Request, ImageInfo)
        case performRemote(Request, RemoteImageInfo)
        case performUpload(Request, UIImage, ImageType)
        case performFile(Request, URL, ImageType)
        var transition: Transition {
            switch self {
            case .performRefresh: .to(.initial, then: .content)
            case .performDelete: .background(.deleting)
            case .performRemote, .performUpload, .performFile: .background(.updating)
            }
        }
    }

    enum BackgroundState { case deleting, updating }
    enum Event { case deleted, updated }
    enum State { case initial, content, error }
    @CommittedPublished
    var item: BaseItemDto {
        didSet { objectWillChange.send() }
    }

    @CommittedPublished
    var images: [ImageType: [ImageInfo]] = [:] {
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

    func refresh() {
        if let request = request() {
            performRefresh(request)
        }
    }

    func deleteImage(_ image: ImageInfo) {
        if let request = request() {
            performDelete(request, image)
        }
    }

    func saveRemoteImage(_ image: RemoteImageInfo) {
        if let request = request() {
            performRemote(request, image)
        }
    }

    func uploadImage(image: UIImage, type: ImageType) {
        if let request = request() {
            performUpload(request, image, type)
        }
    }

    func uploadFile(file: URL, type: ImageType) {
        if let request = request() {
            performFile(request, file, type)
        }
    }

    @Function(\Action.Cases.performRefresh)
    private func _performRefresh(_ request: Request) async throws {
        guard let editor else { throw CancellationError() }
        let updated = try await editor.images(validate: request.validate)
        try request.validate()
        images = updated
    }

    private func apply(_ edit: MetadataImageEdit, request: Request, event: _Event) async throws {
        guard let editor else { throw CancellationError() }
        let updated = try await editor.editImage(edit, validate: request.validate, reloadedItem: { [weak self] updated in
            guard let self, (try? request.validate()) != nil else { return }
            item = updated
            guard (try? request.validate()) != nil else { return }
            Notifications[.itemMetadataDidChange].post(updated)
        })
        guard let updated else { return }
        try request.validate()
        images = updated
        try request.validate()
        events.send(event)
    }

    @Function(\Action.Cases.performDelete)
    private func _performDelete(_ request: Request, _ image: ImageInfo) async throws {
        try await apply(.delete(image), request: request, event: .deleted)
    }

    @Function(\Action.Cases.performRemote)
    private func _performRemote(_ request: Request, _ image: RemoteImageInfo) async throws {
        try await apply(.remote(image), request: request, event: .updated)
    }

    @Function(\Action.Cases.performUpload)
    private func _performUpload(_ request: Request, _ image: UIImage, _ type: ImageType) async throws {
        try request.validate()
        let (data, contentType) = try image.data()
        try request.validate()
        try await apply(.upload(type: type, data: data, contentType: contentType), request: request, event: .updated)
    }

    @Function(\Action.Cases.performFile)
    private func _performFile(_ request: Request, _ file: URL, _ type: ImageType) async throws {
        try request.validate()
        guard file.startAccessingSecurityScopedResource() else { throw ErrorMessage(L10n.unknownError) }
        defer { file.stopAccessingSecurityScopedResource() }
        guard let image = try UIImage(data: Data(contentsOf: file)) else { throw ErrorMessage(L10n.unknownError) }
        try request.validate()
        try await _performUpload(request, image, type)
    }
}
