//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation
import JellyfinAPI
import SwiftfinItemMetadata
import SwiftfinLocalization
import UIKit

@MainActor
@Stateful
final class ItemImageViewModel: ViewModel {

    @CasePathable
    enum Action {
        case deleteImage(ImageInfo)
        case refresh
        case saveRemoteImage(RemoteImageInfo)
        case uploadFile(file: URL, type: ImageType)
        case uploadImage(image: UIImage, type: ImageType)

        var transition: Transition {
            switch self {
            case .refresh:
                .to(.initial, then: .content)
            case .deleteImage:
                .background(.deleting)
            case .saveRemoteImage, .uploadFile, .uploadImage:
                .background(.updating)
            }
        }
    }

    enum BackgroundState {
        case deleting
        case updating
    }

    enum Event {
        case deleted
        case updated
    }

    enum State {
        case initial
        case content
        case error
    }

    @Published
    var item: BaseItemDto

    @Published
    var images: [ImageType: [ImageInfo]] = [:]

    init(item: BaseItemDto) {
        self.item = item
        super.init()
    }

    @Function(\Action.Cases.refresh)
    private func _refresh() async throws {
        guard let itemID = item.id else { return }
        let client = try requireItemMetadata()
        try await refreshImages(using: client, itemID: itemID)
    }

    @Function(\Action.Cases.uploadImage)
    private func _uploadImage(_ image: UIImage, _ type: ImageType) async throws {
        guard let itemID = item.id else { return }
        let client = try requireItemMetadata()
        let (data, contentType) = try image.data()
        try await client.uploadImage(itemID: itemID, type: type, data: data, contentType: contentType)
        try await refreshImages(using: client, itemID: itemID)
        events.send(.updated)
    }

    @Function(\Action.Cases.uploadFile)
    private func _uploadFile(_ file: URL, _ type: ImageType) async throws {
        guard file.startAccessingSecurityScopedResource() else {
            logger.error("Unable to access file at \(file)")
            throw ErrorMessage(L10n.unknownError)
        }
        defer { file.stopAccessingSecurityScopedResource() }

        guard let image = try UIImage(data: Data(contentsOf: file)) else {
            logger.error("Unable to create image from file at \(file)")
            throw ErrorMessage(L10n.unknownError)
        }

        try await _uploadImage(image, type)
    }

    @Function(\Action.Cases.saveRemoteImage)
    private func _saveRemoteImage(_ remoteImageInfo: RemoteImageInfo) async throws {
        guard let itemID = item.id else { return }
        let client = try requireItemMetadata()
        guard try await client.saveRemoteImage(itemID: itemID, image: remoteImageInfo) else { return }
        try await refreshImages(using: client, itemID: itemID)
        events.send(.updated)
    }

    @Function(\Action.Cases.deleteImage)
    private func _deleteImage(_ deleteImageInfo: ImageInfo) async throws {
        guard let itemID = item.id else { return }
        let client = try requireItemMetadata()
        guard try await client.deleteImage(itemID: itemID, image: deleteImageInfo) else { return }
        let updated = try await client.item(id: itemID)
        try client.checkBinding()
        guard item.id == itemID else { throw CancellationError() }
        item = updated
        Notifications[.itemMetadataDidChange].post(updated)
        try await refreshImages(using: client, itemID: itemID)
        events.send(.deleted)
    }

    private func refreshImages(using client: ItemMetadataClient, itemID: String) async throws {
        let updated = try await client.itemImages(itemID: itemID)
        try client.checkBinding()
        guard item.id == itemID else { throw CancellationError() }
        images = updated
    }
}
