//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation
import JellyfinAPI
import SwiftfinNetworking

public enum UserMediaStateError: Error, Sendable { case itemIdentityChanged }
public enum UserMediaStateField: Hashable, Sendable { case played, favorite }

/// User-scoped state mutations do not alter media, metadata or Kids' local/cloud
/// progress schema. The executor checks the exact account before and after I/O.
@MainActor
public final class UserMediaStateClient {
    private let executor: AuthenticatedRequestExecutor
    private let userID: String
    private var tail: Task<Void, Never>?
    public init(executor: AuthenticatedRequestExecutor, userID: String) {
        self.executor = executor
        self.userID = userID
    }

    public func checkBinding() throws {
        try executor.checkBinding()
    }

    public func set(_ field: UserMediaStateField, value: Bool, itemID: String) async throws -> UserItemDataDto {
        try checkBinding()
        let previous = tail
        let operation = Task { @MainActor in
            await previous?.value
            return try await perform(field, value: value, itemID: itemID)
        }
        tail = Task { _ = try? await operation.value }
        return try await withTaskCancellationHandler {
            let result = try await operation.value
            try checkBinding()
            return result
        } onCancel: { operation.cancel() }
    }

    private func perform(_ field: UserMediaStateField, value: Bool, itemID: String) async throws -> UserItemDataDto {
        let result: UserItemDataDto = switch (field, value) {
        case (.played, true): try await executor.value(for: Paths.markPlayedItem(itemID: itemID, userID: userID))
        case (.played, false): try await executor.value(for: Paths.markUnplayedItem(itemID: itemID, userID: userID))
        case (.favorite, true): try await executor.value(for: Paths.markFavoriteItem(itemID: itemID, userID: userID))
        case (.favorite, false): try await executor.value(for: Paths.unmarkFavoriteItem(itemID: itemID, userID: userID))
        }
        if let returnedID = result.itemID, returnedID != itemID {
            throw UserMediaStateError.itemIdentityChanged
        }
        return result
    }
}

/// A completion/rollback belongs to the latest mutation for one displayed item.
/// A later toggle or item replacement invalidates every earlier completion.
@MainActor
public final class UserMediaMutationSequence {
    public struct Ticket: Equatable, Sendable {
        fileprivate let generation: UInt64
        public let itemID: String
        public let field: UserMediaStateField
    }

    private var generation: [UserMediaStateField: UInt64] = [:]
    public init() {}
    public func begin(itemID: String, field: UserMediaStateField) -> Ticket {
        let next = (generation[field] ?? 0) &+ 1
        generation[field] = next
        return .init(generation: next, itemID: itemID, field: field)
    }

    public func accepts(_ ticket: Ticket, currentItemID: String?) -> Bool {
        ticket.generation == generation[ticket.field] && ticket.itemID == currentItemID
    }

    public func invalidate() {
        for field in [UserMediaStateField.played, .favorite] {
            generation[field] = (generation[field] ?? 0) &+ 1
        }
    }
}

public enum UserMediaStatePolicy {
    /// A played response must not overwrite a newer optimistic favorite (and
    /// conversely). Only the state represented by this command is reconciled.
    public static func merge(_ response: UserItemDataDto, into current: UserItemDataDto?, field: UserMediaStateField) -> UserItemDataDto {
        guard var current else { return response }
        current.itemID = response.itemID ?? current.itemID
        current.key = response.key
        switch field {
        case .favorite: current.isFavorite = response.isFavorite
        case .played:
            current.isPlayed = response.isPlayed
            current.lastPlayedDate = response.lastPlayedDate
            current.playCount = response.playCount
            current.playbackPositionTicks = response.playbackPositionTicks
            current.playedPercentage = response.playedPercentage
            current.unplayedItemCount = response.unplayedItemCount
        }
        return current
    }
}
