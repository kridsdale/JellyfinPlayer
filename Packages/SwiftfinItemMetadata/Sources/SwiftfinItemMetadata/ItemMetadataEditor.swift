//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation
import JellyfinAPI

public struct MetadataSubtitleQuery: Equatable, Sendable {
    public let language: String?
    public let perfectMatch: Bool
    public init(language: String?, perfectMatch: Bool) {
        self.language = language
        self.perfectMatch = perfectMatch
    }
}

public enum MetadataImageEdit: Sendable {
    case upload(type: ImageType, data: Data, contentType: String)
    case remote(RemoteImageInfo)
    case delete(ImageInfo)
}

public enum MetadataSubtitleEdit: Sendable {
    case download(Set<String>)
    case upload(data: Data, format: String, language: String, forced: Bool, hearingImpaired: Bool)
    case delete(Set<Int>)
}

/// One original account/item and its edit-then-reload sequences. No native file,
/// image decoding, notification, local record or platform presentation ownership.
@MainActor
public final class ItemMetadataEditor {
    public typealias Checkpoint = @MainActor @Sendable () throws -> Void
    public enum BindingError: Error { case missingItemID }
    public let itemID: String
    private let client: ItemMetadataClient
    private var tail: Task<Void, Never>?
    private var generation: UUID?

    public init(client: ItemMetadataClient, itemID: String) throws {
        try client.checkBinding()
        guard !itemID.isEmpty else { throw BindingError.missingItemID }
        self.client = client
        self.itemID = itemID
    }

    public func checkBinding() throws {
        try client.checkBinding()
    }

    private func check(_ validate: Checkpoint) throws {
        try checkBinding()
        try validate()
    }

    /// Currentness is checked on errors too, so retired work cannot surface a
    /// network/SDK error merely because its transport ignored cancellation.
    private func scoped<Value: Sendable>(
        validate: Checkpoint,
        operation: @MainActor () async throws -> Value
    ) async throws -> Value {
        try check(validate)
        do {
            let value = try await operation()
            try check(validate)
            return value
        } catch {
            try check(validate)
            throw error
        }
    }

    private func mutate<Value: Sendable>(
        validate: @escaping Checkpoint,
        operation: @escaping @MainActor @Sendable () async throws -> Value
    ) async throws -> Value {
        try check(validate)
        let previous = tail, ticket = UUID()
        generation = ticket
        let job = Task {
            await previous?.value
            return try await scoped(validate: validate, operation: operation)
        }
        tail = Task { _ = try? await job.value }
        defer {
            if generation == ticket {
                generation = nil
                tail = nil
            }
        }
        return try await withTaskCancellationHandler {
            let result = try await job.value
            try check(validate)
            return result
        } onCancel: { job.cancel() }
    }

    public func item(validate: @escaping Checkpoint = {}) async throws -> BaseItemDto {
        let pending = tail
        await pending?.value
        return try await scoped(validate: validate) { try await reload(validate: validate) }
    }

    private func reload(validate: Checkpoint) async throws -> BaseItemDto {
        try check(validate)
        let value = try await client.item(id: itemID)
        try check(validate)
        guard value.id == itemID else { throw CancellationError() }
        return value
    }

    public func images(validate: @escaping Checkpoint = {}) async throws -> [ImageType: [ImageInfo]] {
        let pending = tail
        await pending?.value
        return try await scoped(validate: validate) { try await client.itemImages(itemID: itemID) }
    }

    public func deleteItem(validate: @escaping Checkpoint = {}) async throws {
        try await mutate(validate: validate) { try await self.client.deleteItem(id: self.itemID) }
    }

    public func update(_ item: BaseItemDto, validate: @escaping Checkpoint = {}) async throws -> BaseItemDto {
        guard item.id == itemID else { throw CancellationError() }
        return try await mutate(validate: validate) {
            try await self.client.update(itemID: self.itemID, item: item)
            try self.check(validate)
            return try await self.reload(validate: validate)
        }
    }

    /// The inherited five-second refresh settling period is injectable for tests.
    /// A started callback is delivered before the wait; reentry retires follow-up.
    public func refresh(
        options: MetadataRefreshOptions,
        validate: @escaping Checkpoint = {},
        started: @escaping @MainActor @Sendable () -> Void = {},
        wait: @escaping @MainActor @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) async throws -> BaseItemDto {
        try await mutate(validate: validate) {
            try await self.client.refresh(itemID: self.itemID, options: options)
            try self.check(validate)
            started()
            try self.check(validate)
            try await wait(.seconds(5))
            try self.check(validate)
            return try await self.reload(validate: validate)
        }
    }

    /// Deletion preserves its partial item reload/publication before image reload.
    /// Missing remote/image type retains the existing no-op behavior.
    public func editImage(
        _ edit: MetadataImageEdit,
        validate: @escaping Checkpoint = {},
        reloadedItem: @escaping @MainActor @Sendable (BaseItemDto) -> Void = { _ in }
    ) async throws -> [ImageType: [ImageInfo]]? {
        try await mutate(validate: validate) {
            switch edit {
            case let .upload(type, data, contentType):
                try await self.client.uploadImage(itemID: self.itemID, type: type, data: data, contentType: contentType)
            case let .remote(image):
                guard try await self.client.saveRemoteImage(itemID: self.itemID, image: image) else { return nil }
            case let .delete(image):
                guard try await self.client.deleteImage(itemID: self.itemID, image: image) else { return nil }
                try self.check(validate)
                let updated = try await self.reload(validate: validate)
                reloadedItem(updated)
                try self.check(validate)
            }
            try self.check(validate)
            return try await self.client.itemImages(itemID: self.itemID)
        }
    }

    public func searchSubtitles(_ query: MetadataSubtitleQuery, validate: @escaping Checkpoint = {}) async throws -> [RemoteSubtitleInfo] {
        try await scoped(validate: validate) {
            guard let language = query.language, !language.isEmpty else { return [] }
            return try await self.client.searchSubtitles(itemID: self.itemID, language: language, perfectMatch: query.perfectMatch)
        }
    }

    public func editSubtitles(_ edit: MetadataSubtitleEdit, validate: @escaping Checkpoint = {}) async throws -> BaseItemDto {
        try await mutate(validate: validate) {
            switch edit {
            case let .download(ids):
                try await self.client.downloadSubtitles(itemID: self.itemID, subtitleIDs: ids)
            case let .upload(data, format, language, forced, hearingImpaired):
                try await self.client.uploadSubtitle(
                    itemID: self.itemID,
                    data: data,
                    format: format,
                    language: language,
                    forced: forced,
                    hearingImpaired: hearingImpaired
                )
            case let .delete(indices):
                // Keep descending-index deletion and its original indexed error.
                for index in indices.sorted(by: >) {
                    try self.check(validate)
                    try await self.client.deleteSubtitles(itemID: self.itemID, indices: [index])
                }
            }
            try self.check(validate)
            return try await self.reload(validate: validate)
        }
    }
}

public extension ItemMetadataClient {
    func makeEditor(itemID: String) throws -> ItemMetadataEditor {
        try ItemMetadataEditor(client: self, itemID: itemID)
    }
}
