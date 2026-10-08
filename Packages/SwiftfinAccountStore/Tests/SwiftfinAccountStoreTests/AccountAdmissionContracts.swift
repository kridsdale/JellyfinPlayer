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
import SwiftfinAccountStore
import SwiftfinCredentials
import SwiftfinStorage
import SwiftfinStoredValues
import Testing

@MainActor
private final class AdmissionCredentials: CredentialStore {
    var values: [CredentialKey: String] = [:]
    var writes: [CredentialKey] = []
    var onWrite: ((CredentialKey) throws -> Void)?
    func read(_ key: CredentialKey) throws -> String? {
        values[key]
    }

    func write(_ value: String, to key: CredentialKey) throws {
        try onWrite?(key)
        values[key] = value
        writes.append(key)
    }

    func remove(_ key: CredentialKey) throws {
        values[key] = nil
    }
}

@MainActor
private final class AdmissionFixture {
    let directory = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let ownerID = "admission-owner-" + UUID().uuidString
    let serverID = "admission-server-" + UUID().uuidString
    let userID = "admission-user-" + UUID().uuidString
    let otherID = "admission-other-" + UUID().uuidString
    let credentials = AdmissionCredentials()
    let database: SwiftfinDatabase
    let store: LocalAccountStore
    init() async throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        database = SwiftfinDatabase(fileURL: directory.appendingPathComponent("test.sqlite"))
        _ = try await database.open { _, _ in }
        store = .init(credentials: credentials, currentURLName: "Current", database: database, catalogOwnerID: ownerID)
    }

    var endpoint: URL {
        URL(string: "http://example.test:8096/base")!
    }

    var server: ServerAccountRecord {
        .init(urls: [endpoint], currentURL: endpoint, name: "Server", id: serverID, userIDs: [])
    }

    var user: UserAccountRecord {
        .init(id: userID, serverID: serverID, username: "Kid")
    }

    var data: UserDto {
        .init(id: userID, name: "Kid", serverID: serverID)
    }

    func clean() {
        for id in [ownerID, serverID, userID, otherID] {
            UserDefaults(suiteName: id)?.removePersistentDomain(forName: id)
        }
        try? FileManager.default.removeItem(at: directory)
    }

    func commit(
        _ snapshot: UserAdmissionSnapshot,
        policy: LocalUserAccessPolicy = .none,
        pin: String? = nil,
        hint: String? = nil,
        validate: LocalAccountStore.Checkpoint = {}
    ) throws -> UserAccountRecord {
        try store.commitUserAdmission(
            snapshot,
            data: data,
            accessToken: "synthetic-token",
            policy: policy,
            pin: pin,
            pinHint: hint,
            validate: validate
        )
    }

    func connection(_ id: String, url: String = "https://second.test", priority: Int = 1) -> ServerConnection {
        .init(id: id, name: id, url: URL(string: url)!, interface: .any, priority: priority)
    }
}

@Suite(.serialized) @MainActor
struct AccountAdmissionContracts {
    @Test
    func `new admission merges current catalog and retains installed metadata keys`() async throws {
        let f = try await AdmissionFixture()
        defer { f.clean() }
        f.store.servers = [f.server]
        let snapshot = try f.store.prepareUserAdmission(user: f.user, mode: .new, endpoint: f.endpoint)
        let sibling = UserAccountRecord(id: f.otherID, serverID: f.serverID, username: "Sibling")
        f.store.users = [sibling]
        #expect(try f.commit(snapshot, policy: .requirePin, pin: "12345678", hint: "test hint") == f.user)
        #expect(f.store.users == [sibling, f.user])
        #expect(f.store.servers.first?.userIDs == [f.userID])
        #expect(f.credentials.writes == [.accessToken(userID: f.userID), .userPIN(userID: f.userID)])
        #expect(f.store.accessPolicy(userID: f.userID) == .requirePin)
        #expect(f.store.pinHint(userID: f.userID) == "test hint")
        #expect(StoredValues[AccountStorageKeys.userData(userID: f.userID, database: f.database)] == f.data)
    }

    @Test
    func `existing PIN failure prevents replacement and success leaves policy and metadata unchanged`() async throws {
        let f = try await AdmissionFixture()
        defer { f.clean() }
        f.store.servers = [f.server]
        f.store.users = [f.user]
        f.store.setAccessPolicy(.requirePin, userID: f.userID)
        f.store.setPINHint("existing hint", userID: f.userID)
        f.credentials.values[.userPIN(userID: f.userID)] = "87654321"
        f.credentials.values[.accessToken(userID: f.userID)] = "old-token"
        let snapshot = try f.store.prepareUserAdmission(user: f.user, mode: .existing(replaceAccessToken: true), endpoint: f.endpoint)
        #expect(throws: AccountStoreError.incorrectPIN) { try f.commit(snapshot, policy: .requirePin, pin: "wrong") }
        #expect(f.credentials.writes.isEmpty)
        #expect(try f.commit(snapshot, policy: .requirePin, pin: "87654321", hint: "ignored") == f.user)
        #expect(f.credentials.writes == [.accessToken(userID: f.userID)])
        #expect(f.store.pinHint(userID: f.userID) == "existing hint")
        #expect(StoredValues[AccountStorageKeys.userData(userID: f.userID, database: f.database)].id == nil)
    }

    @Test
    func `existing admission without replacement performs no credential or metadata writes`() async throws {
        let f = try await AdmissionFixture()
        defer { f.clean() }
        f.store.servers = [f.server]
        f.store.users = [f.user]
        let snapshot = try f.store.prepareUserAdmission(user: f.user, mode: .existing(replaceAccessToken: false), endpoint: f.endpoint)
        #expect(try f.commit(snapshot) == f.user)
        #expect(f.credentials.writes.isEmpty)
        #expect(f.store.users == [f.user])
    }

    @Test
    func `policy endpoint and local identity changes reject delayed admission before credential writes`() async throws {
        let f = try await AdmissionFixture()
        defer { f.clean() }
        f.store.servers = [f.server]
        f.store.users = [f.user]
        let snapshot = try f.store.prepareUserAdmission(user: f.user, mode: .existing(replaceAccessToken: true), endpoint: f.endpoint)
        f.store.setAccessPolicy(.requireDeviceAuthentication, userID: f.userID)
        #expect(throws: CancellationError.self) { try f.commit(snapshot) }
        f.store.setAccessPolicy(.none, userID: f.userID)
        let catalog = try f.store.connectionCatalog(serverID: f.serverID)
        let second = f.connection("second")
        let added = try f.store.editConnections(.upsert(second), snapshot: catalog)
        try f.store.editConnections(.activate(second), snapshot: added)
        #expect(throws: CancellationError.self) { try f.commit(snapshot) }
        f.store.setActiveConnection(catalog.active, serverID: f.serverID)
        f.store.users = []
        #expect(throws: CancellationError.self) { try f.commit(snapshot) }
        #expect(f.credentials.writes.isEmpty)
    }

    @Test
    func `foreign same user ID and mismatched DTO fail closed`() async throws {
        let f = try await AdmissionFixture()
        defer { f.clean() }
        f.store.servers = [f.server]
        f.store.users = [.init(id: f.userID, serverID: f.otherID, username: "Foreign")]
        #expect(throws: AccountStoreError.identityMismatch) { try f.store.prepareUserAdmission(
            user: f.user,
            mode: .new,
            endpoint: f.endpoint
        ) }
        f.store.users = []
        let snapshot = try f.store.prepareUserAdmission(user: f.user, mode: .new, endpoint: f.endpoint)
        #expect(throws: AccountStoreError.identityMismatch) {
            try f.store.commitUserAdmission(
                snapshot,
                data: .init(id: f.otherID),
                accessToken: "token",
                policy: .none,
                pin: nil,
                pinHint: nil
            )
        }
        #expect(f.credentials.writes.isEmpty && f.store.users.isEmpty)
    }

    @Test
    func `credential failure and retirement preserve only already accepted effects`() async throws {
        let f = try await AdmissionFixture()
        defer { f.clean() }
        f.store.servers = [f.server]
        let snapshot = try f.store.prepareUserAdmission(user: f.user, mode: .new, endpoint: f.endpoint)
        f.credentials.onWrite = { _ in throw CancellationError() }
        #expect(throws: CancellationError.self) { try f.commit(snapshot) }
        #expect(f.credentials.values.isEmpty && f.store.users.isEmpty)
        f.credentials.onWrite = {
            key in if key == .userPIN(userID: f.userID) {
                throw CancellationError()
            }
        }
        #expect(throws: CancellationError.self) { try f.commit(snapshot, policy: .requirePin, pin: "pin") }
        #expect(f.credentials.writes == [.accessToken(userID: f.userID)])
        #expect(f.store.users.isEmpty && f.store.servers == [f.server])
    }

    @Test
    func `retirement after token write stops before PIN catalog policy and metadata`() async throws {
        let f = try await AdmissionFixture()
        defer { f.clean() }
        f.store.servers = [f.server]
        let snapshot = try f.store.prepareUserAdmission(user: f.user, mode: .new, endpoint: f.endpoint)
        #expect(throws: CancellationError.self) { try f.commit(snapshot, policy: .requirePin, pin: "pin", validate: {
            if !f.credentials.writes.isEmpty {
                throw CancellationError()
            }
        }) }
        #expect(f.credentials.writes == [.accessToken(userID: f.userID)])
        #expect(f.store.users.isEmpty && f.store.accessPolicy(userID: f.userID) == .none)
        #expect(StoredValues[AccountStorageKeys.userData(userID: f.userID, database: f.database)].id == nil)
    }

    @Test
    func `registration caches single verified response and concurrent duplicate is never replaced`() async throws {
        let f = try await AdmissionFixture()
        defer { f.clean() }
        let info = PublicSystemInfo(id: f.serverID, serverName: "Server", version: "synthetic")
        #expect(try f.store.registerServer(f.server, info: info))
        #expect(try !f.store.registerServer(f.server, info: .init(id: f.serverID, serverName: "Replacement")))
        #expect(f.store.servers == [f.server])
        #expect(StoredValues[AccountStorageKeys.publicInfo(serverID: f.serverID, database: f.database)] == info)
    }

    @Test
    func `registration stops cache write if its accepted server is removed reentrantly`() async throws {
        let f = try await AdmissionFixture()
        defer { f.clean() }
        #expect(throws: CancellationError.self) { try f.store.registerServer(f.server, info: .init(id: f.serverID), validate: {
            if !f.store.servers.isEmpty {
                f.store.servers = []
            }
        }) }
        #expect(f.store.servers.isEmpty)
        #expect(StoredValues[AccountStorageKeys.publicInfo(serverID: f.serverID, database: f.database)].id == nil)
    }

    @Test
    func `connection edits retain IDs priority active protection and last connection`() async throws {
        let f = try await AdmissionFixture()
        defer { f.clean() }
        f.store.servers = [f.server]
        let original = try f.store.connectionCatalog(serverID: f.serverID)
        #expect(try f.store.connectionCatalog(serverID: f.serverID).connections == original.connections)
        let second = f.connection("second")
        let added = try f.store.editConnections(.upsert(second), snapshot: original)
        let reordered = try f.store.editConnections(.reorder([second.id, original.connections[0].id]), snapshot: added)
        #expect(reordered.connections.map(\.priority) == [0, 1])
        #expect(reordered.active?.id == original.active?.id)
        #expect(try f.store.editConnections(.delete(original.connections[0].id), snapshot: reordered).connections.count == 2)
        let activated = try f.store.editConnections(.activate(reordered.connections[0]), snapshot: reordered)
        let deleted = try f.store.editConnections(.delete(original.connections[0].id), snapshot: activated)
        #expect(deleted.connections.map(\.id) == [second.id])
        #expect(try f.store.editConnections(.delete(second.id), snapshot: deleted).connections.count == 1)
    }

    @Test
    func `delayed connection result rejects changed inventory active endpoint policy or removed server`() async throws {
        let f = try await AdmissionFixture()
        defer { f.clean() }
        f.store.servers = [f.server]
        let original = try f.store.connectionCatalog(serverID: f.serverID)
        let second = f.connection("second")
        let added = try f.store.editConnections(.upsert(second), snapshot: original)
        #expect(throws: CancellationError.self) { try f.store.editConnections(.upsert(f.connection("late")), snapshot: original) }
        let activated = try f.store.editConnections(.activate(second), snapshot: added)
        #expect(throws: CancellationError.self) { try f.store.editConnections(.delete(second.id), snapshot: added) }
        f.store.setAutoSwitchEnabled(true, serverID: f.serverID)
        #expect(throws: CancellationError.self) { try f.store.editConnections(.upsert(f.connection("late")), snapshot: activated) }
        f.store.servers = []
        #expect(throws: CancellationError.self) { try f.store.editConnections(.upsert(second), snapshot: activated) }
        #expect(f.credentials.writes.isEmpty)
    }

    @Test
    func `normalized connection addition deduplicates and activates without replacing siblings`() async throws {
        let f = try await AdmissionFixture()
        defer { f.clean() }
        f.store.servers = [f.server]
        let original = try f.store.connectionCatalog(serverID: f.serverID)
        let url = try #require(URL(string: "HTTP://EXAMPLE.TEST:8096/base/"))
        var generated = 0
        let existing = try f.store.addConnection(url: url, serverID: f.serverID, makeID: { generated += 1
            return "unexpected"
        })
        #expect(generated == 0 && existing == original.active)
        let next = try f.store.addConnection(
            url: #require(URL(string: "https://second.test")),
            serverID: f.serverID,
            makeID: { "second" }
        )
        #expect(f.store.activeConnection(for: f.server) == next)
        #expect(f.store.connections(for: f.server).map(\.id) == [existing.id, "second"])
        #expect(f.store.servers == [f.server] && f.credentials.writes.isEmpty)
    }

    @Test
    func `invalid connection and reorder input reject without accepted writes`() async throws {
        let f = try await AdmissionFixture()
        defer { f.clean() }
        f.store.servers = [f.server]
        let original = try f.store.connectionCatalog(serverID: f.serverID)
        #expect(throws: AccountStoreError.invalidConnection) { try f.store.editConnections(.reorder(["missing"]), snapshot: original) }
        #expect(throws: AccountStoreError.invalidConnection) { try f.store.editConnections(
            .activate(f.connection("missing")),
            snapshot: original
        ) }
        #expect(throws: AccountStoreError.invalidConnection) { try f.store.editConnections(
            .upsert(f.connection("duplicate", url: f.endpoint.absoluteString)),
            snapshot: original
        ) }
        #expect(f.store.connections(for: f.server) == original.connections)
    }

    @Test
    func `retired addition may retain its catalog write but cannot activate afterward`() async throws {
        let f = try await AdmissionFixture()
        defer { f.clean() }
        f.store.servers = [f.server]
        let original = try f.store.connectionCatalog(serverID: f.serverID)
        #expect(throws: CancellationError.self) { try f.store.addConnection(
            url: #require(URL(string: "https://second.test")),
            serverID: f.serverID,
            validate: {
                if f.store.connections(for: f.server).count > 1 {
                    throw CancellationError()
                }
            },
            makeID: { "second" }
        ) }
        #expect(f.store.connections(for: f.server).count == 2)
        #expect(f.store.activeConnection(for: f.server) == original.active)
    }

    @Test
    func `admission and connection receipts cannot cross store instances`() async throws {
        let f = try await AdmissionFixture()
        defer { f.clean() }
        f.store.servers = [f.server]
        let userReceipt = try f.store.prepareUserAdmission(user: f.user, mode: .new, endpoint: f.endpoint)
        let connectionReceipt = try f.store.connectionCatalog(serverID: f.serverID)
        let otherCredentials = AdmissionCredentials()
        let other = LocalAccountStore(
            credentials: otherCredentials,
            currentURLName: "Current",
            database: f.database,
            catalogOwnerID: f.ownerID
        )
        #expect(throws: AccountStoreError.identityMismatch) {
            try other.commitUserAdmission(userReceipt, data: f.data, accessToken: "token", policy: .none, pin: nil, pinHint: nil)
        }
        #expect(throws: CancellationError.self) { try other.editConnections(.upsert(f.connection("second")), snapshot: connectionReceipt) }
        #expect(otherCredentials.values.isEmpty && f.store.users.isEmpty)
    }
}
