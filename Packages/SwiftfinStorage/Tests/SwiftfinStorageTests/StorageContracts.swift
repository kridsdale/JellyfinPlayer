//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

@preconcurrency import CoreStore
import Foundation
@testable import SwiftfinStorage
import Testing

@Suite(.serialized) @MainActor
struct StorageContracts {
    private func temporaryDirectory() throws -> URL {
        let url = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func openLegacy(_ schema: CoreStoreSchema, at url: URL) async throws -> DataStack {
        let stack = DataStack(schema)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            _ = stack.addStorage(SQLiteStore(fileURL: url)) { result in
                switch result { case .success: continuation.resume()
                case let .failure(error): continuation.resume(throwing: error) }
            }
        }
        return stack
    }

    private nonisolated func seedV1(_ stack: DataStack) throws {
        try stack.perform { transaction in
            let server = transaction.create(Into<LegacySwiftfinStore.V1.StoredServer>())
            server.id = "server"
            server.name = "Original"
            server.uris = ["http://192.0.2.1:8096"]
            server.currentURI = "http://192.0.2.1:8096"
            let user = transaction.create(Into<LegacySwiftfinStore.V1.StoredUser>())
            user.id = "user"
            user.username = "Kid"
            user.server = server
            let token = transaction.create(Into<LegacySwiftfinStore.V1.StoredAccessToken>())
            token.value = "synthetic-fixture-only"
            token.user = user
        }
    }

    private nonisolated func seedV2(_ stack: DataStack) throws {
        try stack.perform { transaction in
            let server = transaction.create(Into<LegacySwiftfinStore.V2.StoredServer>())
            server.id = "server"
            server.name = "Original"
            server.urls = [URL(string: "http://192.0.2.1:8096")!]
            server.currentURL = URL(string: "http://192.0.2.1:8096")!
            let user = transaction.create(Into<LegacySwiftfinStore.V2.StoredUser>())
            user.id = "user"
            user.username = "Kid"
            user.server = server
            let row = transaction.create(Into<LegacySwiftfinStore.V2.AnyData>())
            row.ownerID = "user"
            row.domain = "customField"
            row.key = "key"
            row.data = Data([0, 255, 1, 3])
        }
    }

    @Test
    func `unopened database rejects IO without creating A file`() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("Swiftfin.sqlite")
        let db = SwiftfinDatabase(fileURL: url)
        let address = StoredDataAddress(ownerID: "A", field: "f", key: "k")
        #expect(throws: StoredDataError.notOpen) { try db.read(address) }
        #expect(throws: StoredDataError.notOpen) { try db.write(Data([1]), at: address) }
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }

    @Test
    func `original version locks and record JSON remain compatible`() throws {
        let legacy = [LegacySwiftfinStore.V1.schema, LegacySwiftfinStore.V2.schema, LegacySwiftfinStore.V3.schema]
        let moved = [SwiftfinStore.V1.schema, SwiftfinStore.V2.schema, SwiftfinStore.V3.schema]
        for (before, after) in zip(legacy, moved) {
            #expect(before.rawModel().entityVersionHashesByName == after.rawModel().entityVersionHashesByName)
            #expect(before.rawModel().entities.compactMap(\.managedObjectClassName) != after.rawModel().entities
                .compactMap(\.managedObjectClassName))
        }
        let decoder = JSONDecoder()
        let user = try decoder.decode(
            SwiftfinStore.State.User.self,
            from: Data(#"{"id":"user","serverID":"server","username":"Kid"}"#.utf8)
        )
        #expect(user.id == "user")
        let encoded = try JSONSerialization.jsonObject(with: JSONEncoder().encode(user)) as? [String: String]
        #expect(encoded == ["id": "user", "serverID": "server", "username": "Kid"])
    }

    @Test
    func `original V 3 store reopens with opaque bytes intact`() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("Swiftfin.sqlite")
        func seed(_ stack: DataStack) throws {
            try stack.perform { transaction in
                let row = transaction.create(Into<LegacySwiftfinStore.V3.AnyData>())
                row.ownerID = "user"
                row.field = "field"
                row.key = "key"
                row.data = Data([0, 255, 1, 3])
            }
        }
        try await seed(openLegacy(LegacySwiftfinStore.V3.schema, at: url))
        let db = SwiftfinDatabase(fileURL: url)
        let result = try await db.open { _, _ in Issue.record("V3 must not touch credentials") }
        #expect(result == nil)
        #expect(try db.read(.init(ownerID: "user", field: "field", key: "key")) == Data([0, 255, 1, 3]))
    }

    @Test
    func `v 1 migration preserves accounts and credential before replacing legacy store`() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("Swiftfin.sqlite")
        try await seedV1(openLegacy(LegacySwiftfinStore.V1.schema, at: url))
        var saved: [String: String] = [:]
        let db = SwiftfinDatabase(fileURL: url)
        let migration = try await db.open { id, token in saved[id] = token }
        let result = try #require(migration)
        #expect(saved == ["user": "synthetic-fixture-only"])
        #expect(result.users == [.init(id: "user", serverID: "server", username: "Kid")])
        #expect(result.servers.first?.userIDs == ["user"])
        #expect(result.servers.first?.currentURL == URL(string: "http://192.0.2.1:8096"))
        let data = try #require(try db.read(.init(ownerID: "swiftfinApp", field: "users", key: "users")))
        #expect(try JSONDecoder().decode([SwiftfinStore.State.User].self, from: data) == result.users)
        let again = try await db.open { _, _ in Issue.record("Reopening must not copy credentials again") }
        #expect(again == nil)
    }

    @Test
    func `credential failure leaves V 1 readable and retryable`() async throws {
        enum Failure: Error { case denied }
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("Swiftfin.sqlite")
        try await seedV1(openLegacy(LegacySwiftfinStore.V1.schema, at: url))
        let db = SwiftfinDatabase(fileURL: url)
        do { _ = try await db.open { _, _ in throw Failure.denied }
            Issue.record("Expected credential failure")
        } catch Failure.denied {}
        let original = try await openLegacy(LegacySwiftfinStore.V1.schema, at: url)
        let user = try #require(try original.fetchOne(From<LegacySwiftfinStore.V1.StoredUser>()))
        #expect(user.id == "user")
        #expect(user.accessToken?.value == "synthetic-fixture-only")
        var writes = 0
        let retry = try await db.open { _, _ in writes += 1 }
        #expect(retry?.users.first?.id == "user")
        #expect(writes == 1)
    }

    @Test
    func `v 2 migration preserves arbitrary fields without credential writes`() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("Swiftfin.sqlite")
        try await seedV2(openLegacy(LegacySwiftfinStore.V2.schema, at: url))
        let db = SwiftfinDatabase(fileURL: url)
        let result = try await db.open { _, _ in Issue.record("V2 has no SQL credential to move") }
        #expect(result?.users.first?.id == "user")
        #expect(try db.read(.init(ownerID: "user", field: "customField", key: "key")) == Data([0, 255, 1, 3]))
    }

    @Test
    func `byte store reopens and deletes only the selected owner and field`() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("Swiftfin.sqlite")
        let address = StoredDataAddress(ownerID: "A", field: "f", key: "k")
        func seedOriginal() async throws {
            let db = SwiftfinDatabase(fileURL: url)
            _ = try await db.open { _, _ in Issue.record("Fresh store has no credentials") }
            for owner in ["A", "B"] {
                for field in ["f", "g"] {
                    try db.write(Data([1, 2]), at: .init(ownerID: owner, field: field, key: "k"))
                }
            }
            try db.write(Data([3]), at: address)
        }
        try await seedOriginal()
        let reopened = SwiftfinDatabase(fileURL: url)
        _ = try await reopened.open { _, _ in Issue.record("V3 has no credentials") }
        #expect(try reopened.read(address) == Data([3]))
        try reopened.deleteAll(ownerID: "A", field: "f")
        #expect(try reopened.read(address) == nil)
        #expect(try reopened.read(.init(ownerID: "A", field: "g", key: "k")) == Data([1, 2]))
        #expect(try reopened.read(.init(ownerID: "B", field: "f", key: "k")) == Data([1, 2]))
    }

    @Test
    func `observer creates once delivers native changes and cancels queued callbacks`() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let db = SwiftfinDatabase(fileURL: directory.appendingPathComponent("Swiftfin.sqlite"))
        _ = try await db.open { _, _ in }
        let address = StoredDataAddress(ownerID: "A", field: "f", key: "k")
        var delivered = 0
        let observation = try db.observe(address, defaultData: Data([4])) { delivered += 1 }
        #expect(try db.read(address) == Data([4]))
        try db.write(Data([5]), at: address)
        for _ in 0 ..< 100 where delivered == 0 {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(delivered > 0)
        observation.cancel()
        let count = delivered
        try db.write(Data([6]), at: address)
        try await Task.sleep(for: .milliseconds(50))
        #expect(delivered == count)
    }
}
