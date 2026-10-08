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

@MainActor
public protocol AccountAccessTransport: JellyfinRequestSending, JellyfinURLResolving, JellyfinAuthenticating {}
extension JellyfinTransport: AccountAccessTransport {}

public enum AccountAccessError: Error, Sendable { case invalidAuthentication, serverIdentityChanged, userIdentityChanged }
public struct AccountAuthentication: Sendable {
    public let accessToken: String
    public let user: UserDto
    public let userID: String
    public let username: String
    public init(_ result: AuthenticationResult, fallbackUsername: String? = nil) throws {
        guard let accessToken = result.accessToken, let user = result.user, let id = user.id, let name = user.name ?? fallbackUsername
        else { throw AccountAccessError.invalidAuthentication }
        self.accessToken = accessToken
        self.user = user
        self.userID = id
        self.username = name
    }
}

public struct AccountLoginOptions: Sendable {
    public let users: [UserDto]
    public let disclaimer: String?
    public let quickConnectEnabled: Bool
}

/// Public access/login and own-account commands share one captured transport.
/// Credential persistence, local policy evaluation and UI events stay with their
/// existing owners. Authentication never mutates this transport's token.
@MainActor
public final class AccountAccessClient {
    private let transport: any AccountAccessTransport
    let executor: AuthenticatedRequestExecutor
    private let expectedServerID: String?
    public init(
        transport: any AccountAccessTransport,
        expectedServerID: String? = nil,
        isCurrent: @escaping @MainActor @Sendable () -> Bool = { true }
    ) {
        self.transport = transport
        self.expectedServerID = expectedServerID
        self.executor = .init(sender: transport, isCurrent: isCurrent)
    }

    public func checkBinding() throws {
        try executor.checkBinding()
    }

    public func publicInfo(expectedServerID: String? = nil) async throws -> JellyfinResponse<PublicSystemInfo> {
        let response = try await executor.response(for: Paths.getPublicSystemInfo)
        if let expectedServerID = expectedServerID ?? self.expectedServerID,
           response.value.id != expectedServerID
        {
            throw AccountAccessError.serverIdentityChanged
        }
        return response
    }

    public func loginOptions() async throws -> AccountLoginOptions {
        async let users = executor.value(for: Paths.getPublicUsers)
        async let branding = executor.value(for: Paths.getBrandingOptions)
        async let enabled = executor.value(for: Paths.getQuickConnectEnabled)
        let result = try await (users, branding, enabled)
        try checkBinding()
        let disclaimer = result.1.loginDisclaimer.flatMap { $0.isEmpty ? nil : $0 }
        return .init(users: result.0, disclaimer: disclaimer, quickConnectEnabled: Self.decodeBoolean(result.2))
    }

    public func signIn(username: String, password: String, fallbackUsername: String? = nil) async throws -> AccountAuthentication {
        try await authenticate(fallbackUsername: fallbackUsername) { try await self.transport.authenticate(
            username: username,
            password: password
        ) }
    }

    public func signIn(quickConnectSecret: String) async throws -> AccountAuthentication {
        try await authenticate { try await self.transport.authenticate(quickConnectSecret: quickConnectSecret) }
    }

    private func authenticate(
        fallbackUsername: String? = nil,
        _ operation: @MainActor () async throws -> AuthenticationResult
    ) async throws -> AccountAuthentication {
        try checkBinding()
        do {
            let result = try await operation()
            try checkBinding()
            if let expectedServerID, result.serverID != expectedServerID {
                throw AccountAccessError.serverIdentityChanged
            }
            return try .init(result, fallbackUsername: fallbackUsername)
        } catch { try checkBinding()
            throw error
        }
    }

    public func currentUser(expectedUserID: String) async throws -> UserDto {
        let user = try await executor.value(for: Paths.getCurrentUser)
        guard user.id == expectedUserID else { throw AccountAccessError.userIdentityChanged }
        return user
    }

    public func authorizeQuickConnect(code: String, userID: String) async throws -> Bool {
        let bytes = try await executor.value(for: Paths.authorizeQuickConnect(code: code, userID: userID))
        return Self.decodeBoolean(bytes)
    }

    public func resetPassword(userID: String, current: String, new: String) async throws {
        try await executor.complete(Paths.updateUserPassword(userID: userID, .init(currentPw: current, newPw: new)))
    }

    public func splashURL() throws -> URL? {
        try checkBinding()
        let url = transport.url(with: Paths.getSplashscreen(), queryAPIKey: false)
        try checkBinding()
        return url
    }

    public func profileURL(userID: String, imageTag: String?) throws -> URL? {
        try checkBinding()
        let url = transport.url(with: Paths.getUserImage(parameters: .init(userID: userID, tag: imageTag)), queryAPIKey: false)
        try checkBinding()
        return url
    }

    private static func decodeBoolean(_ bytes: Data) -> Bool {
        (try? JSONDecoder().decode(Bool.self, from: bytes)) ?? false
    }
}
