//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation
import JellyfinAPI
import SwiftfinAccountModels
import SwiftfinCredentials
import SwiftfinStorage
import SwiftfinStoredValues

public enum AccountStoreError: Error, Sendable { case identityMismatch, incorrectPIN, invalidConnection }

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

    /// Preserves credential-first local admission. Failures are not a cross-store transaction.
    public func saveAuthenticatedUser(_ user: UserAccountRecord, accessToken: String, pin: String? = nil) throws {
        try storeAccessToken(accessToken, userID: user.id)
        if let pin {
            try storePIN(pin, userID: user.id)
        }
        replaceUserRecord(user)
        var records = servers
        if let index = records.firstIndex(where: { $0.id == user.serverID }) {
            let server = records[index]
            let ids = server.userIDs.contains(user.id) ? server.userIDs : server.userIDs + [user.id]
            records[index] = .init(
                urls: server.urls,
                currentURL: server.currentURL,
                name: server.name,
                id: server.id,
                userIDs: ids
            )
            servers = records
        }
    }

    /// Install the explicitly supplied local account records after successful authentication.
    /// This retains the Kids admission order and replaces only matching record identities.
    public func saveAuthenticatedAccount(_ server: ServerAccountRecord, user: UserAccountRecord, accessToken: String) throws {
        guard user.serverID == server.id, server.userIDs.contains(user.id) else {
            throw AccountStoreError.identityMismatch
        }
        try storeAccessToken(accessToken, userID: user.id)
        var records = servers
        records.removeAll { $0.id == server.id }
        records.append(server)
        servers = records
        replaceUserRecord(user)
    }

    private func replaceUserRecord(_ user: UserAccountRecord) {
        var records = users
        records.removeAll { $0.id == user.id }
        records.append(user)
        users = records
    }

    /// Merge with the current inventory rather than a pre-request snapshot.
    /// Record writes precede cached DTO writes, preserving installed behavior;
    /// StoredValues retains its existing nonthrowing storage-failure semantics.
    @discardableResult
    public func updateServerMetadata(serverID: String, info: PublicSystemInfo) throws -> Bool {
        guard info.id == serverID else { throw AccountStoreError.identityMismatch }
        let records = servers
        guard let current = records.first(where: { $0.id == serverID }) else { return false }
        let updated = ServerAccountRecord(
            urls: current.urls, currentURL: current.currentURL,
            name: info.serverName ?? current.name, id: current.id, userIDs: current.userIDs
        )
        servers = records.map { $0.id == serverID ? updated : $0 }
        StoredValues[AccountStorageKeys.publicInfo(serverID: serverID, database: database)] = info
        return true
    }

    @discardableResult
    public func updateUserMetadata(userID: String, serverID: String, data: UserDto) throws -> Bool {
        guard data.id == userID, data.serverID == nil || data.serverID == serverID else { throw AccountStoreError.identityMismatch }
        let records = users
        guard let current = records.first(where: { $0.id == userID }) else { return false }
        guard current.serverID == serverID else { throw AccountStoreError.identityMismatch }
        let updated = UserAccountRecord(id: current.id, serverID: current.serverID, username: data.name ?? current.username)
        users = records.map { $0.id == userID ? updated : $0 }
        StoredValues[AccountStorageKeys.userData(userID: userID, database: database)] = data
        return true
    }

    public func pin(userID: String) throws -> String? {
        try credentials.read(.userPIN(userID: userID))
    }

    public func storePIN(_ pin: String, userID: String) throws {
        try credentials.write(pin, to: .userPIN(userID: userID))
    }

    /// Exact installed String comparison. Missing PINs fail admission by default;
    /// the security editor explicitly permits absence when checking an old PIN.
    /// Credential read failures propagate and no settings or credentials are changed.
    public func matchesPIN(_ candidate: String, userID: String, allowMissing: Bool = false) throws -> Bool {
        guard let stored = try pin(userID: userID) else { return allowMissing }
        return candidate == stored
    }

    /// Preserves credential-first ordering and the installed nontransactional
    /// settings writes. A credential failure leaves both policy and hint unchanged.
    public func setLocalSecurity(userID: String, policy: LocalUserAccessPolicy, pin: String, hint: String) throws {
        if policy == .requirePin {
            try storePIN(pin, userID: userID)
        } else {
            try credentials.remove(.userPIN(userID: userID))
        }
        setAccessPolicy(policy, userID: userID)
        setPINHint(hint, userID: userID)
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

public extension LocalAccountStore {
    typealias Checkpoint = @MainActor @Sendable () throws -> Void

    /// Snapshot local identity/policy and the exact endpoint before UI authentication.
    /// Global user-ID storage cannot represent the same ID on two different servers.
    func prepareUserAdmission(user: UserAccountRecord, mode: UserAdmissionMode, endpoint: URL) throws -> UserAdmissionSnapshot {
        try Task.checkCancellation()
        guard !user.id.isEmpty, let server = servers.first(where: { $0.id == user.serverID }),
              effectiveURL(for: server) == endpoint else { throw AccountStoreError.identityMismatch }
        let existing = users.first { $0.id == user.id }
        guard existing == nil || existing?.serverID == user.serverID else { throw AccountStoreError.identityMismatch }
        switch mode {
        case .new: guard existing == nil else { throw AccountStoreError.identityMismatch }
        case .existing: guard existing == user else { throw AccountStoreError.identityMismatch }
        }
        return UserAdmissionSnapshot(
            owner: ObjectIdentifier(self),
            user: user,
            mode: mode,
            existing: existing,
            endpoint: endpoint,
            policy: accessPolicy(userID: user.id)
        )
    }

    /// Retains credential-first, nontransactional admission. Reentrant/cancelled
    /// input is checked between effects; accepted local writes are never rolled back.
    func commitUserAdmission(
        _ snapshot: UserAdmissionSnapshot, data: UserDto, accessToken: String,
        policy: LocalUserAccessPolicy, pin: String?, pinHint: String?, validate: Checkpoint = {}
    ) throws -> UserAccountRecord {
        guard snapshot.owner == ObjectIdentifier(self), data.id == snapshot.user.id,
              data.serverID == nil || data.serverID == snapshot.user.serverID,
              !accessToken.isEmpty else { throw AccountStoreError.identityMismatch }
        var expectedUser = snapshot.existing
        var expectedPolicy = snapshot.policy
        func check() throws {
            try Task.checkCancellation()
            try validate()
            guard let server = servers.first(where: { $0.id == snapshot.user.serverID }),
                  effectiveURL(for: server) == snapshot.endpoint,
                  users.first(where: { $0.id == snapshot.user.id }) == expectedUser,
                  accessPolicy(userID: snapshot.user.id) == expectedPolicy
            else { throw CancellationError() }
        }
        try check()
        switch snapshot.mode {
        case let .existing(replaceAccessToken):
            guard policy == snapshot.policy else { throw CancellationError() }
            if policy == .requirePin, pin == nil {
                throw AccountStoreError.incorrectPIN
            }
            if let pin {
                let matches = try matchesPIN(pin, userID: snapshot.user.id)
                try check()
                guard matches else { throw AccountStoreError.incorrectPIN }
            }
            if replaceAccessToken {
                try storeAccessToken(accessToken, userID: snapshot.user.id)
                try check()
            }
        case .new:
            if policy == .requirePin, pin == nil {
                throw AccountStoreError.incorrectPIN
            }
            try storeAccessToken(accessToken, userID: snapshot.user.id)
            try check()
            if let pin {
                try storePIN(pin, userID: snapshot.user.id)
                try check()
            }
            expectedUser = snapshot.user
            replaceUserRecord(snapshot.user)
            try check()
            var records = servers
            guard let index = records.firstIndex(where: { $0.id == snapshot.user.serverID }) else { throw CancellationError() }
            let server = records[index]
            if !server.userIDs.contains(snapshot.user.id) {
                records[index] = .init(
                    urls: server.urls,
                    currentURL: server.currentURL,
                    name: server.name,
                    id: server.id,
                    userIDs: server.userIDs + [snapshot.user.id]
                )
                servers = records
                try check()
            }
            expectedPolicy = policy
            setAccessPolicy(policy, userID: snapshot.user.id)
            try check()
            StoredValues[AccountStorageKeys.userData(userID: snapshot.user.id, database: database)] = data
            try check()
            if let pinHint {
                setPINHint(pinHint, userID: snapshot.user.id)
                try check()
            }
        }
        try check()
        return snapshot.user
    }

    /// Merge the one verified public-info result; no second network request.
    /// Returns false for a concurrently registered duplicate and never replaces it.
    @discardableResult
    func registerServer(_ server: ServerAccountRecord, info: PublicSystemInfo, validate: Checkpoint = {}) throws -> Bool {
        try Task.checkCancellation()
        try validate()
        guard !server.id.isEmpty, info.id == server.id else { throw AccountStoreError.identityMismatch }
        guard !servers.contains(where: { $0.id == server.id }) else { return false }
        servers = servers + [server]
        try Task.checkCancellation()
        try validate()
        guard servers.first(where: { $0.id == server.id }) == server else { throw CancellationError() }
        StoredValues[AccountStorageKeys.publicInfo(serverID: server.id, database: database)] = info
        try Task.checkCancellation()
        try validate()
        guard servers.first(where: { $0.id == server.id }) == server else { throw CancellationError() }
        return true
    }

    /// Existing local connection catalog is authoritative; append a normalized URL
    /// once and retain stable IDs. Only local settings are changed.
    func addConnection(
        url: URL,
        serverID: String,
        validate: Checkpoint = {},
        makeID: () -> String = { UUID().uuidString }
    ) throws -> ServerConnection {
        try Task.checkCancellation()
        try validate()
        var snapshot = try connectionCatalog(serverID: serverID)
        try validate()
        let normalized = ServerConnection.normalizedURL(url) ?? url
        let connection: ServerConnection
        if let existing = snapshot.connections.first(where: { $0.url == normalized }) {
            connection = existing
        } else {
            connection = .init(
                id: makeID(),
                name: normalized.absoluteString,
                url: normalized,
                interface: .any,
                priority: snapshot.connections.count
            )
            snapshot = try editConnections(.upsert(connection), snapshot: snapshot, validate: validate)
        }
        try editConnections(.activate(connection), snapshot: snapshot, validate: validate)
        return connection
    }
}
