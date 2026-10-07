//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

// Swiftfin is subject to the Mozilla Public License, v2.0.
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
import Defaults
import Foundation
import JellyfinAPI
import SwiftfinAccountModels
import SwiftfinAccountStore
import SwiftfinCredentials
import SwiftfinStorage
import SwiftfinStoredValues
import Testing

@MainActor
private final class MetadataCredentials: CredentialStore {
    var calls = 0
    func read(_ key: CredentialKey) throws -> String? {
        calls += 1
        return nil
    }

    func write(_ value: String, to key: CredentialKey) throws {
        calls += 1
    }

    func remove(_ key: CredentialKey) throws {
        calls += 1
    }
}

@MainActor
private final class MetadataFixture {
    let directory = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let owner = "metadata-contract-" + UUID().uuidString
    let serverID = "metadata-server-" + UUID().uuidString
    let userID = "metadata-user-" + UUID().uuidString
    let otherID = "metadata-other-" + UUID().uuidString
    let database: SwiftfinDatabase
    let credentials = MetadataCredentials()
    let store: LocalAccountStore
    init() async throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        database = SwiftfinDatabase(fileURL: directory.appendingPathComponent("test.sqlite"))
        _ = try await database.open { _, _ in }
        store = LocalAccountStore(credentials: credentials, currentURLName: "Current", database: database, catalogOwnerID: owner)
    }

    func clean() {
        for id in [owner, serverID, userID, otherID] {
            UserDefaults(suiteName: id)?.removePersistentDomain(forName: id)
        }
        try? FileManager.default.removeItem(at: directory)
    }

    func server(_ id: String, name: String = "Server") -> ServerAccountRecord {
        let url = URL(string: "https://example.test/base")!
        return .init(urls: [url], currentURL: url, name: name, id: id, userIDs: [userID, otherID])
    }

    var user: UserAccountRecord {
        .init(id: userID, serverID: serverID, username: "Kid")
    }
}

@Suite(.serialized) @MainActor
struct AccountMetadataContracts {
    @Test
    func `installed keys keep defaults and SQL destinations`() {
        let info = AccountStorageKeys.publicInfo(serverID: "server")
        let user = AccountStorageKeys.userData(userID: "user")
        #expect(info.ownerID == "server" && info.name == "publicInfo" && info.field == "publicInfo" && info.storage == .defaults)
        #expect(user.ownerID == "user" && user.name == "userData" && user.field == "userData")
        #if os(tvOS)
        #expect(user.storage == .defaults)
        #else
        #expect(user.storage == .sql)
        #endif
    }

    @Test
    func `original SDKJSON and defaults bridge remain readable`() async throws {
        let f = try await MetadataFixture()
        defer { f.clean() }
        let infoJSON = "{\"Id\":\"\(f.serverID)\",\"ServerName\":\"Original\",\"Version\":\"10.11.0\"}"
        let userJSON = "{\"Id\":\"\(f.userID)\",\"ServerId\":\"\(f.serverID)\",\"Name\":\"Original Kid\",\"PrimaryImageTag\":\"image\"}"
        let infoSuite = try #require(UserDefaults(suiteName: f.serverID))
        infoSuite.set(infoJSON, forKey: "publicInfo")
        let userSuite = try #require(UserDefaults(suiteName: f.userID))
        userSuite.set(userJSON, forKey: "userData")
        try f.database.write(Data(userJSON.utf8), at: .init(ownerID: f.userID, field: "userData", key: "userData"))
        let infoKey = AccountStorageKeys.publicInfo(serverID: f.serverID, database: f.database)
        let userKey = AccountStorageKeys.userData(userID: f.userID, database: f.database)
        let info = StoredValues[infoKey]
        let user = StoredValues[userKey]
        #expect(info.id == f.serverID && info.serverName == "Original" && info.version == "10.11.0")
        #expect(user.id == f.userID && user.serverID == f.serverID && user.primaryImageTag == "image")
        let legacyUserKey = Defaults.Key<UserDto>("userData", default: .init(), suite: userSuite)
        #expect(Defaults[legacyUserKey].name == "Original Kid")
        StoredValues[infoKey] = info
        StoredValues[userKey] = user
        let rewrittenInfo = try #require(infoSuite.string(forKey: "publicInfo"))
        #expect(try JSONDecoder().decode(PublicSystemInfo.self, from: Data(rewrittenInfo.utf8)) == info)
        #if !os(tvOS)
        let rewrittenUser = try #require(try f.database.read(.init(ownerID: f.userID, field: "userData", key: "userData")))
        #expect(try JSONDecoder().decode(UserDto.self, from: rewrittenUser) == user)
        #endif
    }

    @Test
    func `server merge uses current records and preserves siblings connections and order`() async throws {
        let f = try await MetadataFixture()
        defer { f.clean() }
        let sibling = f.server(f.otherID, name: "Unrelated")
        let old = f.server(f.serverID)
        f.store.servers = [old, sibling]
        let changedURL = try #require(URL(string: "https://changed.test/path"))
        let changed = ServerAccountRecord(
            urls: [changedURL, old.currentURL],
            currentURL: changedURL,
            name: "Locally edited",
            id: f.serverID,
            userIDs: [f.otherID, f.userID]
        )
        f.store.servers = [sibling, changed]
        let info = PublicSystemInfo(id: f.serverID, serverName: "Refreshed", version: "10.11.1")
        #expect(try f.store.updateServerMetadata(serverID: f.serverID, info: info))
        let expected = ServerAccountRecord(
            urls: changed.urls,
            currentURL: changed.currentURL,
            name: "Refreshed",
            id: f.serverID,
            userIDs: changed.userIDs
        )
        #expect(f.store.servers == [sibling, expected])
        #expect(StoredValues[AccountStorageKeys.publicInfo(serverID: f.serverID, database: f.database)] == info)
        #expect(UserDefaults(suiteName: f.otherID)?.persistentDomain(forName: f.otherID)?["publicInfo"] == nil)
        #expect(f.credentials.calls == 0)
    }

    @Test
    func `user merge preserves adjacent accounts and omitted server ID is accepted`() async throws {
        let f = try await MetadataFixture()
        defer { f.clean() }
        let sibling = UserAccountRecord(id: f.otherID, serverID: f.otherID, username: "Other")
        f.store.users = [sibling, f.user]
        let data = UserDto(id: f.userID, name: "Renamed", primaryImageTag: "tag")
        #expect(try f.store.updateUserMetadata(userID: f.userID, serverID: f.serverID, data: data))
        #expect(f.store.users == [sibling, .init(id: f.userID, serverID: f.serverID, username: "Renamed")])
        #expect(StoredValues[AccountStorageKeys.userData(userID: f.userID, database: f.database)] == data)
        #expect(StoredValues[AccountStorageKeys.userData(userID: f.otherID, database: f.database)].id == nil)
        #expect(f.credentials.calls == 0)
    }

    @Test
    func `nil names preserve local names and duplicate record mapping`() async throws {
        let f = try await MetadataFixture()
        defer { f.clean() }
        let server = f.server(f.serverID, name: "Keep")
        f.store.servers = [server, server]
        f.store.users = [f.user, f.user]
        #expect(try f.store.updateServerMetadata(serverID: f.serverID, info: .init(id: f.serverID)))
        #expect(try f.store.updateUserMetadata(userID: f.userID, serverID: f.serverID, data: .init(id: f.userID, serverID: f.serverID)))
        #expect(f.store.servers == [server, server])
        #expect(f.store.users == [f.user, f.user])
    }

    @Test
    func `missing records are not recreated and caches are not written`() async throws {
        let f = try await MetadataFixture()
        defer { f.clean() }
        f.store.servers = [f.server(f.serverID)]
        f.store.users = [f.user]
        f.store.servers = []
        f.store.users = []
        #expect(try !f.store.updateServerMetadata(serverID: f.serverID, info: .init(id: f.serverID, serverName: "Late")))
        #expect(try !f.store.updateUserMetadata(
            userID: f.userID,
            serverID: f.serverID,
            data: .init(id: f.userID, name: "Late", serverID: f.serverID)
        ))
        #expect(f.store.servers.isEmpty && f.store.users.isEmpty)
        #expect(UserDefaults(suiteName: f.serverID)?.persistentDomain(forName: f.serverID)?["publicInfo"] == nil)
        #expect(UserDefaults(suiteName: f.userID)?.persistentDomain(forName: f.userID)?["userData"] == nil)
        #expect(try f.database.read(.init(ownerID: f.userID, field: "userData", key: "userData")) == nil)
        #expect(f.credentials.calls == 0)
    }

    @Test
    func `mismatched payload or stored server rejects before any mutation`() async throws {
        let f = try await MetadataFixture()
        defer { f.clean() }
        let server = f.server(f.serverID)
        f.store.servers = [server]
        f.store.users = [f.user]
        for invalid in [PublicSystemInfo(), .init(id: f.otherID)] {
            #expect(throws: AccountStoreError.identityMismatch) { try f.store.updateServerMetadata(serverID: f.serverID, info: invalid) }
        }
        for invalid in [UserDto(), .init(id: f.otherID), .init(id: f.userID, name: "Wrong", serverID: f.otherID)] {
            #expect(throws: AccountStoreError.identityMismatch) { try f.store.updateUserMetadata(
                userID: f.userID,
                serverID: f.serverID,
                data: invalid
            ) }
        }
        #expect(throws: AccountStoreError.identityMismatch) { try f.store.updateUserMetadata(
            userID: f.userID,
            serverID: f.otherID,
            data: .init(id: f.userID, serverID: f.otherID)
        ) }
        #expect(f.store.servers == [server] && f.store.users == [f.user])
        #expect(UserDefaults(suiteName: f.serverID)?.persistentDomain(forName: f.serverID)?["publicInfo"] == nil)
        #expect(try f.database.read(.init(ownerID: f.userID, field: "userData", key: "userData")) == nil)
        #expect(f.credentials.calls == 0)
    }
}
