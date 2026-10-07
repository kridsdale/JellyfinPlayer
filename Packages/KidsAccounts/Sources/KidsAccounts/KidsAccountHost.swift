//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

// SPDX-License-Identifier: MPL-2.0
import Combine
import Foundation
import KidsDomain

/// Full network identity. Credential replacement is an identity change even for the same user.
/// Descriptions deliberately disclose no credentials or household connection details.
public struct KidsAccountIdentity: Equatable, Hashable, Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    public let serverURL: URL
    public let serverID: String
    public let serverName: String
    public let userID: String
    public let accessToken: String

    public init(serverURL: URL, serverID: String, serverName: String, userID: String, accessToken: String) {
        self.serverURL = serverURL
        self.serverID = serverID
        self.serverName = serverName
        self.userID = userID
        self.accessToken = accessToken
    }

    public var description: String {
        "KidsAccountIdentity(redacted)"
    }

    public var debugDescription: String {
        description
    }

    // A display-name change must not invalidate an otherwise identical authorized stream.
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.serverURL == rhs.serverURL && lhs.serverID == rhs.serverID &&
            lhs.userID == rhs.userID && lhs.accessToken == rhs.accessToken
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(serverURL)
        hasher.combine(serverID)
        hasher.combine(userID)
        hasher.combine(accessToken)
    }

    public func matches(_ binding: KidsBinding) -> Bool {
        binding.isValid && serverID == binding.serverID && userID == binding.userID
    }
}

/// SDK-specific authentication data stays inside the host's activation closure.
/// The application must verify policy and the exact libraries before activation.
@MainActor
public final class KidsAuthenticatedAccount {
    public let identity: KidsAccountIdentity
    private let credentialStorage: @MainActor () throws -> Void
    private let activation: @MainActor () async throws -> Void
    private var preparedBinding: KidsBinding?

    public init(
        identity: KidsAccountIdentity,
        credentialStorage: @escaping @MainActor () throws -> Void = {},
        activation: @escaping @MainActor () async throws -> Void
    ) {
        self.identity = identity
        self.credentialStorage = credentialStorage
        self.activation = activation
    }

    /// Store the host credentials after catalog authorization, before saving the application binding.
    public func prepareActivation(binding: KidsBinding) throws {
        guard identity.matches(binding) else { throw KidsContractError.denied }
        try credentialStorage()
        preparedBinding = binding
    }

    public func activate(binding: KidsBinding) async throws {
        guard preparedBinding == binding, identity.matches(binding) else { throw KidsContractError.denied }
        try await activation()
    }
}

/// Account lifecycle and secure local credentials belong to the application host.
/// Catalog/policy authorization and playback progress belong to their own libraries.
@MainActor
public protocol KidsAccountHost: AnyObject {
    var currentIdentity: KidsAccountIdentity? { get }
    var identityChanges: AnyPublisher<KidsAccountIdentity?, Never> { get }
    var parentPIN: String? { get throws }
    func storeParentPIN(_ pin: String) throws
    func authenticate(
        url: URL,
        serverID: String,
        serverName: String,
        username: String,
        password: String
    ) async throws -> KidsAuthenticatedAccount
    func signOut() async
}
