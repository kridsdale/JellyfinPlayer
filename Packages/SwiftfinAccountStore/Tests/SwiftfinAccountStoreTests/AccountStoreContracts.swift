//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation
import SwiftfinAccountModels
import SwiftfinAccountStore
import SwiftfinCredentials
import SwiftfinStorage
import SwiftfinStoredValues
import Testing

@MainActor
private final class MemoryCredentials: CredentialStore {
    var values: [CredentialKey: String] = [:]
    var removals: [CredentialKey] = []
    var writeError: CredentialStoreError?
    func read(_ key: CredentialKey) throws -> String? {
        values[key]
    }

    func write(_ value: String, to key: CredentialKey) throws {
        if let writeError {
            throw writeError
        }
        values[key] = value
    }

    func remove(_ key: CredentialKey) throws {
        removals.append(key)
        values[key] = nil
    }
}

@MainActor
private final class Fixture {
    let directory = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let ownerID = "account-test-" + UUID().uuidString
    let serverID = "account-test-server-" + UUID().uuidString
    let userID = "account-test-user-" + UUID().uuidString
    let otherID = "account-test-other-" + UUID().uuidString
    let database: SwiftfinDatabase
    let credentials = MemoryCredentials()
    let store: LocalAccountStore
    init() async throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        database = SwiftfinDatabase(fileURL: directory.appendingPathComponent("Swiftfin.sqlite"))
        _ = try await database.open { _, _ in }
        store = LocalAccountStore(credentials: credentials, currentURLName: "Current URL", database: database, catalogOwnerID: ownerID)
    }

    func clean() {
        for id in [ownerID, serverID, userID, otherID] {
            UserDefaults(suiteName: id)?.removePersistentDomain(forName: id)
        }
        try? FileManager.default.removeItem(at: directory)
    }

    var server: ServerAccountRecord {
        let current = URL(string: "HTTP://EXAMPLE.TEST:8096/base/")!
        return .init(
            urls: [current, URL(string: "https://z.test/")!, URL(string: "https://a.test/")!],
            currentURL: current,
            name: "Server",
            id: serverID,
            userIDs: [userID]
        )
    }

    var user: UserAccountRecord {
        .init(id: userID, serverID: serverID, username: "Kid")
    }

    func seedOpaqueMetadata(owner: String) throws {
        try database.write(Data("opaque SDK metadata".utf8), at: .init(ownerID: owner, field: "userData", key: "userData"))
        UserDefaults(suiteName: owner)?.set("opaque defaults", forKey: "publicInfo")
    }
}

@Suite(.serialized) @MainActor
struct AccountStoreContracts {
    @Test
    func `production key inventory preserves literal installed addresses and destinations`() {
        let servers = AccountStorageKeys.servers()
        let users = AccountStorageKeys.users()
        #expect(servers.ownerID == "swiftfinApp" && servers.name == "servers" && servers.field == "servers")
        #expect(users.ownerID == "swiftfinApp" && users.name == "users" && users.field == "users")
        let connection = AccountStorageKeys.connections(serverID: "server")
        let active = AccountStorageKeys.activeConnectionID(serverID: "server")
        let switching = AccountStorageKeys.autoSwitchEnabled(serverID: "server")
        #expect(connection.name == "serverConnections" && connection.field == "serverConnections" && connection.ownerID == "server")
        #expect(active.name == "activeServerConnectionID" && active.field == "activeServerConnectionID")
        #expect(switching.name == "isAutoSwitchEnabled" && switching.field == "isAutoSwitchEnabled")
        #expect(connection.storage == .defaults && active.storage == .defaults && switching.storage == .defaults)
        let policy = AccountStorageKeys.accessPolicy(userID: "user")
        let hint = AccountStorageKeys.pinHint(userID: "user")
        #expect(policy.name == "accessPolicy" && policy.field == "accessPolicy" && policy.ownerID == "user")
        #expect(hint.name == "pinHint" && hint.field == "pinHint" && hint.ownerID == "user")
        #if os(tvOS)
        #expect(servers.storage == .defaults && users.storage == .defaults && policy.storage == .defaults && hint.storage == .defaults)
        #else
        #expect(servers.storage == .sql && users.storage == .sql && policy.storage == .sql && hint.storage == .sql)
        #endif
    }

    @Test
    func `frozen pre-extraction account JSON remains readable and preserves unrelated fields`() async throws {
        let f = try await Fixture()
        defer { f.clean() }
        // Seed original JSON fields directly, without encoding moved models.
        let serverJSON = "{\"id\":\"\(f.serverID)\",\"name\":\"Server\",\"currentURL\":\"http://example.test:8096\",\"urls\":[\"http://example.test:8096\",\"https://fallback.test\"],\"userIDs\":[\"\(f.userID)\"]}"
        let userJSON = "{\"id\":\"\(f.userID)\",\"serverID\":\"\(f.serverID)\",\"username\":\"Kid\"}"
        try f.database.write(Data(("[" + serverJSON + "]").utf8), at: .init(ownerID: f.ownerID, field: "servers", key: "servers"))
        try f.database.write(Data(("[" + userJSON + "]").utf8), at: .init(ownerID: f.ownerID, field: "users", key: "users"))
        let server = try #require(f.store.servers.first)
        #expect(server.id == f.serverID && server.userIDs == [f.userID] && server.urls.count == 2)
        #expect(f.store.users == [f.user])
        f.store.servers = [server]
        let rewritten = try #require(try f.database.read(.init(ownerID: f.ownerID, field: "servers", key: "servers")))
        #expect(try JSONDecoder().decode([ServerAccountRecord].self, from: rewritten) == [server])
    }

    @Test
    func `default connections retain URL identity ordering and are persisted only by ensure`() async throws {
        let f = try await Fixture()
        defer { f.clean() }
        let suite = try #require(UserDefaults(suiteName: f.serverID))
        let defaults = f.store.connections(for: f.server)
        #expect(defaults.map(\.url.absoluteString) == ["http://example.test:8096/base", "https://a.test", "https://z.test"])
        #expect(defaults.map(\.priority) == [0, 1, 2])
        #expect(defaults.first?.name == "Current URL")
        #expect(suite.object(forKey: "serverConnections") == nil)
        let persisted = f.store.ensureConnections(for: f.server)
        #expect(f.store.ensureConnections(for: f.server) == persisted)
        #expect(try f.store.hasConnection(url: #require(URL(string: "HTTP://EXAMPLE.TEST:8096/base/")), server: f.server))
        #expect(f.store.effectiveURL(for: f.server).absoluteString == "http://example.test:8096/base")
    }

    @Test
    func `legacy connection strings and invalid active IDs retain installed fallback semantics`() async throws {
        let f = try await Fixture()
        defer { f.clean() }
        let suite = try #require(UserDefaults(suiteName: f.serverID))
        suite.set(
            [
                #"{"id":"wifi","name":"Home","url":"http://example.test:8096/base","interface":"wifi","wifiSSIDs":["Home"],"priority":4}"#,
                #"{"id":"remote","name":"Remote","url":"https://fallback.test","interface":"any","wifiSSIDs":[],"priority":0}"#
            ],
            forKey: "serverConnections"
        )
        suite.set("missing", forKey: "activeServerConnectionID")
        #expect(f.store.activeConnection(for: f.server)?.id == "wifi")
        let ordered = f.store.connections(for: f.server)
        #expect(ordered.map(\.id) == ["remote", "wifi"])
        f.store.setConnections(Array(ordered.reversed()), serverID: f.serverID)
        #expect(f.store.connections(for: f.server).map(\.id) == ["wifi", "remote"])
        f.store.setActiveConnection(ordered.first, serverID: f.serverID)
        #expect(f.store.activeConnection(for: f.server)?.id == "remote")
        #expect(f.store.effectiveURL(for: f.server).absoluteString == "https://fallback.test")
        f.store.setActiveConnection(nil, serverID: f.serverID)
        #expect(suite.string(forKey: "activeServerConnectionID") == "")
    }

    @Test
    func `local account policy and PIN hint keep exact SQL keys and owner isolation`() async throws {
        let f = try await Fixture()
        defer { f.clean() }
        try f.database.write(Data(#""requirePin""#.utf8), at: .init(ownerID: f.userID, field: "accessPolicy", key: "accessPolicy"))
        try f.database.write(Data(#""hint""#.utf8), at: .init(ownerID: f.userID, field: "pinHint", key: "pinHint"))
        #expect(f.store.accessPolicy(userID: f.userID) == .requirePin)
        #expect(f.store.pinHint(userID: f.userID) == "hint")
        #expect(f.store.accessPolicy(userID: f.otherID) == .none)
        f.store.setAccessPolicy(.requireDeviceAuthentication, userID: f.userID)
        f.store.setPINHint("new hint", userID: f.userID)
        #expect(f.store.pinHint(userID: f.otherID).isEmpty)
        #expect(f.store.pinHint(userID: f.userID) == "new hint")
        f.store.setAutoSwitchEnabled(true, serverID: f.serverID)
        #expect(f.store.autoSwitchEnabled(serverID: f.serverID))
        #expect(!f.store.autoSwitchEnabled(serverID: f.otherID))
    }

    @Test
    func `user removal clears only its settings and PIN and retains adjacent credentials`() async throws {
        let f = try await Fixture()
        defer { f.clean() }
        let otherUser = UserAccountRecord(id: f.otherID, serverID: f.serverID, username: "Other")
        f.store.users = [f.user, otherUser]
        f.store.servers = [ServerAccountRecord(
            urls: f.server.urls,
            currentURL: f.server.currentURL,
            name: f.server.name,
            id: f.serverID,
            userIDs: [f.userID, f.otherID]
        )]
        try f.seedOpaqueMetadata(owner: f.userID)
        try f.seedOpaqueMetadata(owner: f.otherID)
        f.credentials.values = [
            .userPIN(userID: f.userID): "test PIN",
            .accessToken(userID: f.userID): "test token",
            .parentPIN: "test parent PIN"
        ]
        try f.store.deleteUser(f.user)
        #expect(f.store.users == [otherUser])
        #expect(f.store.servers.first?.userIDs == [f.otherID])
        #expect(try f.database.read(.init(ownerID: f.userID, field: "userData", key: "userData")) == nil)
        #expect(try f.database.read(.init(ownerID: f.otherID, field: "userData", key: "userData")) != nil)
        #expect(UserDefaults(suiteName: f.userID)?.object(forKey: "publicInfo") == nil)
        #expect(UserDefaults(suiteName: f.otherID)?.string(forKey: "publicInfo") == "opaque defaults")
        #expect(f.credentials.removals == [.userPIN(userID: f.userID)])
        #expect(f.credentials.values[.accessToken(userID: f.userID)] == "test token")
        #expect(f.credentials.values[.parentPIN] == "test parent PIN")
    }

    @Test
    func `server removal includes all matching local users and retains unrelated owners and credentials`() async throws {
        let f = try await Fixture()
        defer { f.clean() }
        let secondUser = UserAccountRecord(id: f.userID + "-second", serverID: f.serverID, username: "Second")
        defer { UserDefaults(suiteName: secondUser.id)?.removePersistentDomain(forName: secondUser.id) }
        let otherUser = UserAccountRecord(id: f.otherID, serverID: f.otherID, username: "Other")
        let otherServer = try ServerAccountRecord(
            urls: [],
            currentURL: #require(URL(string: "https://other.test")),
            name: "Other",
            id: f.otherID,
            userIDs: [f.otherID]
        )
        f.store.users = [f.user, secondUser, otherUser]
        f.store.servers = [f.server, otherServer]
        for id in [f.serverID, f.userID, secondUser.id, f.otherID] {
            try f.seedOpaqueMetadata(owner: id)
        }
        f.credentials.values[.userPIN(userID: f.userID)] = "test PIN"
        try f.store.deleteServer(f.server)
        #expect(f.store.servers == [otherServer] && f.store.users == [otherUser])
        for id in [f.serverID, f.userID, secondUser.id] {
            #expect(try f.database.read(.init(ownerID: id, field: "userData", key: "userData")) == nil)
            #expect(UserDefaults(suiteName: id)?.object(forKey: "publicInfo") == nil)
        }
        #expect(try f.database.read(.init(ownerID: f.otherID, field: "userData", key: "userData")) != nil)
        #expect(UserDefaults(suiteName: f.otherID)?.string(forKey: "publicInfo") == "opaque defaults")
        #expect(f.credentials.removals.isEmpty)
        #expect(f.credentials.values[.userPIN(userID: f.userID)] == "test PIN")
    }

    @Test
    func `credential replacement errors propagate without changing policy or stored credentials`() async throws {
        let f = try await Fixture()
        defer { f.clean() }
        f.credentials.values[.accessToken(userID: f.userID)] = "old test token"
        f.credentials.values[.userPIN(userID: f.userID)] = "old test PIN"
        f.store.setAccessPolicy(.requirePin, userID: f.userID)
        f.credentials.writeError = .system(operation: .write, status: -25293)
        #expect(throws: CredentialStoreError.self) { try f.store.storeAccessToken("new test token", userID: f.userID) }
        #expect(throws: CredentialStoreError.self) { try f.store.storePIN("new test PIN", userID: f.userID) }
        #expect(try f.store.accessToken(userID: f.userID) == "old test token")
        #expect(try f.store.pin(userID: f.userID) == "old test PIN")
        #expect(f.store.accessPolicy(userID: f.userID) == .requirePin)
    }
}
