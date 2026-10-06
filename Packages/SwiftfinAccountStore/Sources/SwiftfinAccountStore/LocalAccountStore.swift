//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation
import SwiftfinAccountModels
import SwiftfinCredentials
import SwiftfinStorage
import SwiftfinStoredValues

/// Owns local account records, their scoped settings and credential operations.
/// It neither contacts a server nor resolves an application session/global.
@MainActor
public final class LocalAccountStore {
    private let database: SwiftfinDatabase
    private let credentials: any CredentialStore
    private let catalogOwnerID: String
    private let currentURLName: String

    public init(
        credentials: any CredentialStore,
        currentURLName: String,
        database: SwiftfinDatabase = .shared,
        catalogOwnerID: String = "swiftfinApp"
    ) {
        self.credentials = credentials
        self.currentURLName = currentURLName
        self.database = database
        self.catalogOwnerID = catalogOwnerID
    }

    public var servers: [ServerAccountRecord] {
        get { StoredValues[AccountStorageKeys.servers(ownerID: catalogOwnerID, database: database)] }
        set { StoredValues[AccountStorageKeys.servers(ownerID: catalogOwnerID, database: database)] = newValue }
    }

    public var users: [UserAccountRecord] {
        get { StoredValues[AccountStorageKeys.users(ownerID: catalogOwnerID, database: database)] }
        set { StoredValues[AccountStorageKeys.users(ownerID: catalogOwnerID, database: database)] = newValue }
    }

    public func connections(for server: ServerAccountRecord) -> [ServerConnection] {
        let stored = StoredValues[AccountStorageKeys.connections(serverID: server.id, database: database)]
        return stored.isEmpty ? defaultConnections(for: server) : ServerConnection.ordered(stored)
    }

    public func setConnections(_ connections: [ServerConnection], serverID: String) {
        StoredValues[AccountStorageKeys.connections(serverID: serverID, database: database)] = ServerConnection.ordered(
            connections,
            preservingOrder: true
        )
    }

    @discardableResult
    public func ensureConnections(for server: ServerAccountRecord) -> [ServerConnection] {
        let stored = StoredValues[AccountStorageKeys.connections(serverID: server.id, database: database)]
        guard stored.isEmpty else { return ServerConnection.ordered(stored) }
        let result = defaultConnections(for: server)
        setConnections(result, serverID: server.id)
        return result
    }

    public func activeConnection(for server: ServerAccountRecord) -> ServerConnection? {
        let connections = connections(for: server)
        let activeID = StoredValues[AccountStorageKeys.activeConnectionID(serverID: server.id, database: database)]
        if !activeID.isEmpty, let active = connections.first(where: { $0.id == activeID }) {
            return active
        }
        let currentURL = ServerConnection.normalizedURL(server.currentURL) ?? server.currentURL
        return connections.first { $0.url == currentURL } ?? connections.first
    }

    public func setActiveConnection(_ connection: ServerConnection?, serverID: String) {
        StoredValues[AccountStorageKeys.activeConnectionID(serverID: serverID, database: database)] = connection?.id ?? ""
    }

    public func effectiveURL(for server: ServerAccountRecord) -> URL {
        activeConnection(for: server)?.url ?? server.currentURL
    }

    public func hasConnection(url: URL, server: ServerAccountRecord) -> Bool {
        let normalized = ServerConnection.normalizedURL(url) ?? url
        return connections(for: server).contains { $0.url == normalized }
    }

    public func autoSwitchEnabled(serverID: String) -> Bool {
        StoredValues[AccountStorageKeys.autoSwitchEnabled(serverID: serverID, database: database)]
    }

    public func setAutoSwitchEnabled(_ enabled: Bool, serverID: String) {
        StoredValues[AccountStorageKeys.autoSwitchEnabled(serverID: serverID, database: database)] = enabled
    }

    public func accessPolicy(userID: String) -> LocalUserAccessPolicy {
        StoredValues[AccountStorageKeys.accessPolicy(userID: userID, database: database)]
    }

    public func setAccessPolicy(_ policy: LocalUserAccessPolicy, userID: String) {
        StoredValues[AccountStorageKeys.accessPolicy(userID: userID, database: database)] = policy
    }

    public func pinHint(userID: String) -> String {
        StoredValues[AccountStorageKeys.pinHint(userID: userID, database: database)]
    }

    public func setPINHint(_ hint: String, userID: String) {
        StoredValues[AccountStorageKeys.pinHint(userID: userID, database: database)] = hint
    }

    public func accessToken(userID: String) throws -> String? {
        try credentials.read(.accessToken(userID: userID))
    }

    public func storeAccessToken(_ token: String, userID: String) throws {
        try credentials.write(token, to: .accessToken(userID: userID))
    }

    public func pin(userID: String) throws -> String? {
        try credentials.read(.userPIN(userID: userID))
    }

    public func storePIN(_ pin: String, userID: String) throws {
        try credentials.write(pin, to: .userPIN(userID: userID))
    }

    public func deleteSettings(userID: String) throws {
        try database.deleteAll(ownerID: userID)
        clearDefaults(ownerID: userID)
    }

    /// Preserves the existing deletion sequence and PIN-only secure cleanup.
    /// Database/credential failures propagate; this is not a cross-store transaction.
    public func deleteUser(_ user: UserAccountRecord) throws {
        users.removeAll { $0.id == user.id }
        try deleteSettings(userID: user.id)
        var records = servers
        if let index = records.firstIndex(where: { $0.id == user.serverID }) {
            let server = records[index]
            records[index] = ServerAccountRecord(
                urls: server.urls, currentURL: server.currentURL, name: server.name,
                id: server.id, userIDs: server.userIDs.filter { $0 != user.id }
            )
            servers = records
        }
        try credentials.remove(.userPIN(userID: user.id))
    }

    /// Only local account/settings stores are touched. Credentials retain the
    /// prior server-removal behavior; no server catalog or media operation exists.
    public func deleteServer(_ server: ServerAccountRecord) throws {
        let removedUsers = users.filter { $0.serverID == server.id }
        for user in removedUsers {
            try database.deleteAll(ownerID: user.id)
        }
        try database.deleteAll(ownerID: server.id)
        clearDefaults(ownerID: server.id)
        users.removeAll { $0.serverID == server.id }
        servers.removeAll { $0.id == server.id }
        for user in removedUsers {
            clearDefaults(ownerID: user.id)
        }
    }

    private func defaultConnections(for server: ServerAccountRecord) -> [ServerConnection] {
        let urls = [server.currentURL] + server.urls.subtracting([server.currentURL]).sorted { $0.absoluteString < $1.absoluteString }
        return urls.enumerated().map { index, url in
            let normalized = ServerConnection.normalizedURL(url) ?? url
            return ServerConnection(
                id: UUID().uuidString, name: url == server.currentURL ? currentURLName : normalized.absoluteString,
                url: normalized, interface: .any, priority: index
            )
        }
    }

    private func clearDefaults(ownerID: String) {
        guard let suite = UserDefaults(suiteName: ownerID) else { return }
        // Match the prior per-key removal so installed Defaults observers still fire.
        for key in suite.dictionaryRepresentation().keys {
            suite.removeObject(forKey: key)
        }
    }
}
