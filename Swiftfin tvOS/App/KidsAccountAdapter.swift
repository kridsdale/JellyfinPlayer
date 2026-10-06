//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Combine
import FactoryKit
import Foundation
import JellyfinAPI
import KidsAccounts
import KidsCatalog
import KidsDomain

// SPDX-License-Identifier: MPL-2.0
import SwiftfinStoredValues

/// Composition adapter for the retained Swiftfin secure account lifecycle.
/// No SDK user, global container, or Keychain type crosses the kids account port.
@MainActor
final class SwiftfinKidsAccountHost: KidsAccountHost {
    private let sessions: UserSessionManager
    private let pinKey = "kids.parentPin.v1"

    init(sessions: UserSessionManager) {
        self.sessions = sessions
    }

    private static func identity(from session: UserSession?) -> KidsAccountIdentity? {
        guard let session else { return nil }
        return KidsAccountIdentity(
            serverURL: session.server.effectiveServerURL,
            serverID: session.server.id,
            serverName: session.server.name,
            userID: session.user.id,
            accessToken: session.user.accessToken
        )
    }

    var currentIdentity: KidsAccountIdentity? {
        Self.identity(from: sessions.currentSession)
    }

    var identityChanges: AnyPublisher<KidsAccountIdentity?, Never> {
        sessions.$currentSession
            .receive(on: DispatchQueue.main)
            .map { session in MainActor.assumeIsolated { Self.identity(from: session) } }
            .removeDuplicates()
            .eraseToAnyPublisher()
    }

    var parentPIN: String? {
        Container.shared.keychainService().get(pinKey)
    }

    func storeParentPIN(_ pin: String) throws {
        guard Container.shared.keychainService().set(pin, forKey: pinKey) else { throw KidsAPIError.invalidResponse }
    }

    func authenticate(
        url: URL,
        serverID: String,
        serverName: String,
        username: String,
        password: String
    ) async throws -> KidsAuthenticatedAccount {
        let client = JellyfinClient(configuration: .swiftfinConfiguration(url: url))
        let result = try await client.signIn(username: username, password: password)
        guard let token = result.accessToken, let user = result.user, let userID = user.id else { throw KidsAPIError.authentication }
        let identity = KidsAccountIdentity(serverURL: url, serverID: serverID, serverName: serverName, userID: userID, accessToken: token)
        return KidsAuthenticatedAccount(identity: identity, credentialStorage: {
            let keychain = Container.shared.keychainService()
            guard keychain.set(token, forKey: "\(userID)-accessToken") else { throw KidsAPIError.invalidResponse }
            let server = ServerState(urls: [url], currentURL: url, name: serverName, id: serverID, userIDs: [userID])
            var servers = StoredValues[.Server.servers]
            servers.removeAll { $0.id == serverID }
            servers.append(server)
            StoredValues[.Server.servers] = servers
            let saved = UserState(id: userID, serverID: serverID, username: user.name ?? username)
            saved.data = user
            saved.accessPolicy = .none
            var users = StoredValues[.User.users]
            users.removeAll { $0.id == userID }
            users.append(saved)
            StoredValues[.User.users] = users
        }) { [sessions] in
            try await sessions.signIn(userID: userID)
        }
    }

    func signOut() async {
        await sessions.signOut(reason: .explicit)
    }
}
