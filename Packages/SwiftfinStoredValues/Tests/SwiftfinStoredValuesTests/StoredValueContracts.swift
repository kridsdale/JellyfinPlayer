//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Combine
import Defaults
import Foundation
import SwiftfinStorage
@testable import SwiftfinStoredValues
import Testing

@Suite(.serialized) @MainActor
struct StoredValueContracts {
    @Test
    func `exact legacy defaults suite and key names are preserved`() throws {
        let owner = "storage-test-" + UUID().uuidString
        let suite = try #require(UserDefaults(suiteName: owner))
        defer { suite.removePersistentDomain(forName: owner) }
        for (field, resolved) in [(nil, "name"), ("name", "name"), ("field", "field-name")] as [(String?, String)] {
            let legacy = Defaults.Key<Int>(resolved, suite: suite, default: { 0 })
            Defaults[legacy] = 19
            let key = StoredValues.Key("name", ownerID: owner, field: field, storage: .defaults, default: 0)
            #expect(StoredValues[key] == 19)
            StoredValues[key] = 23
            #expect(Defaults[legacy] == 23)
        }
    }

    @Test
    func `invalid and always keys cannot write or observe storage`() {
        let key = StoredValues.Key(always: 17)
        let observation = StoredValueObservation(key)
        observation.value = 33
        #expect(observation.value == 17)
        let empty = StoredValues.Key("", ownerID: "storage-test-" + UUID().uuidString, field: "field", storage: .sql, default: 19)
        StoredValues[empty] = 40
        #expect(StoredValues[empty] == 19)
    }

    @Test
    func `independent SQL addresses preserve legacy JSON and corruption fallback`() async throws {
        let directory = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let db = SwiftfinDatabase(fileURL: directory.appendingPathComponent("Swiftfin.sqlite"))
        _ = try await db.open { _, _ in }
        let key = StoredValues.Key("key", ownerID: "A", field: "f", storage: .sql, default: [1, 2], database: db)
        let other = StoredValues.Key("key", ownerID: "B", field: "f", storage: .sql, default: [3], database: db)
        #expect(StoredValues[key] == [1, 2])
        StoredValues[key] = [4, 5]
        #expect(StoredValues[other] == [3])
        let bytes = try #require(try db.read(.init(ownerID: "A", field: "f", key: "key")))
        #expect(try JSONDecoder().decode([Int].self, from: bytes) == [4, 5])
        try db.write(Data([255]), at: .init(ownerID: "A", field: "f", key: "key"))
        #expect(StoredValues[key] == [1, 2])
        #expect(try db.read(.init(ownerID: "A", field: "f", key: "key")) == Data([255]))
    }

    @Test
    func `observable SQL values publish external changes and release their owner`() async throws {
        let directory = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let db = SwiftfinDatabase(fileURL: directory.appendingPathComponent("Swiftfin.sqlite"))
        _ = try await db.open { _, _ in }
        let key = StoredValues.Key("key", ownerID: "A", field: "f", storage: .sql, default: 1, database: db)
        var owner: StoredValueObservation<Int>? = StoredValueObservation(key)
        weak let weakOwner = owner
        var notifications = 0
        let subscription = try #require(owner?.objectWillChange.sink { notifications += 1 })
        try db.write(JSONEncoder().encode(7), at: .init(ownerID: "A", field: "f", key: "key"))
        for _ in 0 ..< 100 where notifications == 0 {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(notifications > 0)
        #expect(owner?.value == 7)
        subscription.cancel()
        owner = nil
        #expect(weakOwner == nil)
    }

    @Test
    func `observable defaults receive external writes and release their owner`() async throws {
        let ownerID = "storage-test-" + UUID().uuidString
        let suite = try #require(UserDefaults(suiteName: ownerID))
        defer { suite.removePersistentDomain(forName: ownerID) }
        let key = StoredValues.Key("key", ownerID: ownerID, field: "f", storage: .defaults, default: 1)
        var owner: StoredValueObservation<Int>? = StoredValueObservation(key)
        weak let weakOwner = owner
        var notifications = 0
        let subscription = try #require(owner?.objectWillChange.sink { notifications += 1 })
        await Task.yield()
        Defaults[Defaults.Key<Int>("f-key", suite: suite, default: { 1 })] = 7
        for _ in 0 ..< 100 where notifications == 0 {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(notifications > 0)
        #expect(owner?.value == 7)
        subscription.cancel()
        owner = nil
        for _ in 0 ..< 20 where weakOwner != nil {
            await Task.yield()
        }
        #expect(weakOwner == nil)
    }
}
