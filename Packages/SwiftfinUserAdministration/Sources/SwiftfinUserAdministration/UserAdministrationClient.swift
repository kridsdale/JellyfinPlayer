//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation
import Get
import JellyfinAPI
import SwiftfinCollections
import SwiftfinNetworking

/// Server account and policy administration; no device/process/media editing API.
@MainActor
public final class UserAdministrationClient {
    private let executor: AuthenticatedRequestExecutor
    private let currentUserID: String
    public init(executor: AuthenticatedRequestExecutor, currentUserID: String) {
        self.executor = executor
        self.currentUserID = currentUserID
    }

    public func checkBinding() throws {
        try executor.checkBinding()
    }

    public func users(isHidden: Bool? = nil, isDisabled: Bool? = nil) async throws -> [UserDto] {
        try await executor.value(for: Paths.getUsers(isHidden: isHidden, isDisabled: isDisabled))
    }

    public func user(id: String) async throws -> UserDto {
        try await executor.value(for: Paths.getUserByID(userID: id))
    }

    public func create(
        name: String,
        password: String
    ) async throws -> UserDto {
        try await executor.value(for: Paths.createUserByName(CreateUserByName(
            name: name,
            password: password
        )))
    }

    public func libraries(isHidden: Bool?) async throws -> [BaseItemDto] {
        try await executor
            .value(for: Paths.getMediaFolders(isHidden: isHidden)).items ?? []
    }

    public func updatePolicy(id: String, policy: UserPolicy) async throws {
        try await executor.complete(Paths.updateUserPolicy(
            userID: id,
            policy
        ))
    }

    public func updateConfiguration(id: String, configuration: UserConfiguration) async throws {
        try await executor.complete(Paths.updateUserConfiguration(
            userID: id,
            configuration
        ))
    }

    public func updateUser(id: String, user: UserDto) async throws {
        try await executor.complete(Paths.updateUser(userID: id, user))
    }

    /// One captured owner for the entire concurrent batch; self-deletion is excluded.
    @discardableResult
    public func deleteUsers(ids: [String]) async throws -> Set<String> {
        try executor.checkBinding()
        let eligible = Set(ids).subtracting([currentUserID])
        try await withThrowingTaskGroup(of: Void.self) { group in
            for id in eligible.sorted() {
                group.addTask { try await self.executor.complete(Paths.deleteUser(userID: id)) }
            }
            try await group.waitForAll()
        }
        try executor.checkBinding()
        return eligible
    }

    public static func sortedUsers(_ users: [UserDto]) -> [UserDto] {
        users.sorted(using: \.name)
    }

    public static func filterValue(_ enabled: Bool) -> Bool? {
        enabled ? true : nil
    }
}

public extension UserAdministrationClient {
    func uploadImage(userID: String, data: Data, contentType: String) async throws {
        var request = Paths.postUserImage(userID: userID, data.base64EncodedData())
        request.headers = ["Content-Type": contentType]
        try await executor.complete(request)
    }

    func deleteImage(userID: String) async throws {
        try await executor.complete(Paths.deleteUserImage(userID: userID))
    }
}
