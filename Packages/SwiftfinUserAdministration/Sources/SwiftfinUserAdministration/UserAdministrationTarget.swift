//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation
import JellyfinAPI

/// A selected user and its original authenticated transport. Serial writes retain
/// their predecessor until the sender really finishes, including cancellation.
@MainActor
public final class UserAdministrationTarget {
    public enum TargetError: Error { case missingUserID }
    public let userID: String
    private let client: UserAdministrationClient
    private var generation: UUID?
    private var tail: Task<Void, Never>?

    init(client: UserAdministrationClient, userID: String) throws {
        guard !userID.isEmpty else { throw TargetError.missingUserID }
        self.client = client
        self.userID = userID
    }

    public func checkBinding() throws {
        try client.checkBinding()
    }

    public func user() async throws -> UserDto {
        let user = try await client.user(id: userID)
        guard user.id == userID else { throw CancellationError() }
        return user
    }

    public func libraries(isHidden: Bool?) async throws -> [BaseItemDto] {
        try await client.libraries(isHidden: isHidden)
    }

    public func updatePolicy(_ policy: UserPolicy) async throws {
        let client = client, userID = userID
        try await write { try await client.updatePolicy(id: userID, policy: policy) }
    }

    /// Read the selected user's latest profile after preceding writes have drained.
    /// Never send a cached profile that belongs to another user or old edit state.
    public func updateUsername(_ username: String) async throws {
        let client = client, userID = userID
        try await write {
            var user = try await client.user(id: userID)
            try client.checkBinding()
            guard user.id == userID else { throw CancellationError() }
            user.name = username
            try await client.updateUser(id: userID, user: user)
        }
    }

    private func write(_ operation: @escaping @MainActor @Sendable () async throws -> Void) async throws {
        try checkBinding()
        let client = client
        let previous = tail
        let ticket = UUID()
        generation = ticket
        let task = Task {
            await previous?.value
            try Task.checkCancellation()
            try client.checkBinding()
            try await operation()
            try client.checkBinding()
        }
        tail = Task { _ = try? await task.value }
        defer {
            if generation == ticket {
                generation = nil
                tail = nil
            }
        }
        try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
        }
        try checkBinding()
    }
}
