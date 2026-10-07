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
import Testing

private enum SecurityFailure: Error { case read, write, remove }

@MainActor
private final class SecurityCredentials: CredentialStore {
    var values: [CredentialKey: String] = [:]
    var reads: [CredentialKey] = []
    var writes: [CredentialKey] = []
    var removals: [CredentialKey] = []
    var failure: SecurityFailure?
    var willMutate: (@MainActor () -> Void)?

    func read(_ key: CredentialKey) throws -> String? {
        reads.append(key)
        if failure == .read {
            throw SecurityFailure.read
        }
        return values[key]
    }

    func write(_ value: String, to key: CredentialKey) throws {
        writes.append(key)
        willMutate?()
        if failure == .write {
            throw SecurityFailure.write
        }
        values[key] = value
    }

    func remove(_ key: CredentialKey) throws {
        removals.append(key)
        willMutate?()
        if failure == .remove {
            throw SecurityFailure.remove
        }
        values[key] = nil
    }
}

@MainActor
private final class SecurityFixture {
    let directory = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let userID = "security-user-" + UUID().uuidString
    let siblingID = "security-sibling-" + UUID().uuidString
    let database: SwiftfinDatabase
    let credentials = SecurityCredentials()
    let store: LocalAccountStore
    var observedPolicy: LocalUserAccessPolicy?
    var observedHint: String?

    init() async throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        database = SwiftfinDatabase(fileURL: directory.appendingPathComponent("security.sqlite"))
        _ = try await database.open { _, _ in }
        store = LocalAccountStore(credentials: credentials, currentURLName: "Test URL", database: database)
    }

    func observeCredentialBoundary() {
        credentials.willMutate = { [weak self] in
            guard let self else { return }
            observedPolicy = store.accessPolicy(userID: userID)
            observedHint = store.pinHint(userID: userID)
        }
    }

    func clean() {
        credentials.willMutate = nil
        for id in [userID, siblingID] {
            UserDefaults(suiteName: id)?.removePersistentDomain(forName: id)
        }
        try? FileManager.default.removeItem(at: directory)
    }
}

@Suite(.serialized) @MainActor
struct LocalSecurityContracts {
    @Test
    func `comparison keeps exact case whitespace empty and Unicode behavior`() async throws {
        let f = try await SecurityFixture()
        defer { f.clean() }
        for (stored, candidate, expected) in [
            ("12345678", "12345678", true),
            ("12345678", "1234567", false),
            ("12345678", " 12345678", false),
            ("Kid", "kid", false),
            ("", "", true),
            ("", "0", false),
            ("café", "cafe\u{301}", true),
        ] {
            f.credentials.values[.userPIN(userID: f.userID)] = stored
            let result = try f.store.matchesPIN(candidate, userID: f.userID)
            #expect(result == expected)
        }
        #expect(f.credentials.writes.isEmpty && f.credentials.removals.isEmpty)
    }

    @Test
    func `missing PIN fails admission but old PIN verification explicitly permits absence`() async throws {
        let f = try await SecurityFixture()
        defer { f.clean() }
        for candidate in ["", "12345678"] {
            let admission = try f.store.matchesPIN(candidate, userID: f.userID)
            let oldPIN = try f.store.matchesPIN(candidate, userID: f.userID, allowMissing: true)
            #expect(!admission && oldPIN)
        }
        f.credentials.values[.userPIN(userID: f.userID)] = "existing"
        let mismatch = try f.store.matchesPIN("other", userID: f.userID, allowMissing: true)
        #expect(!mismatch)
    }

    @Test
    func `credential read failure propagates even when absence would be permitted`() async throws {
        let f = try await SecurityFixture()
        defer { f.clean() }
        f.credentials.failure = .read
        #expect(throws: SecurityFailure.read) { try f.store.matchesPIN("test", userID: f.userID) }
        #expect(throws: SecurityFailure.read) { try f.store.matchesPIN("test", userID: f.userID, allowMissing: true) }
        #expect(f.credentials.reads == [.userPIN(userID: f.userID), .userPIN(userID: f.userID)])
        #expect(f.credentials.writes.isEmpty && f.credentials.removals.isEmpty)
    }

    @Test
    func `require PIN commits credential before policy and hint and touches only this user`() async throws {
        let f = try await SecurityFixture()
        defer { f.clean() }
        f.store.setAccessPolicy(.requireDeviceAuthentication, userID: f.userID)
        f.store.setPINHint("old hint", userID: f.userID)
        f.store.setAccessPolicy(.none, userID: f.siblingID)
        f.store.setPINHint("sibling hint", userID: f.siblingID)
        f.credentials.values = [
            .userPIN(userID: f.userID): "old fixture PIN",
            .userPIN(userID: f.siblingID): "sibling fixture PIN",
            .accessToken(userID: f.userID): "fixture token",
            .parentPIN: "fixture parent PIN",
        ]
        let original = f.credentials.values
        f.observeCredentialBoundary()
        try f.store.setLocalSecurity(userID: f.userID, policy: .requirePin, pin: "new fixture PIN", hint: "new hint")
        #expect(f.observedPolicy == .requireDeviceAuthentication && f.observedHint == "old hint")
        #expect(f.store.accessPolicy(userID: f.userID) == .requirePin && f.store.pinHint(userID: f.userID) == "new hint")
        #expect(f.store.accessPolicy(userID: f.siblingID) == .none && f.store.pinHint(userID: f.siblingID) == "sibling hint")
        var expected = original
        expected[.userPIN(userID: f.userID)] = "new fixture PIN"
        #expect(f.credentials.values == expected && f.credentials.writes == [.userPIN(userID: f.userID)])
        #expect(f.credentials.reads.isEmpty && f.credentials.removals.isEmpty)
    }

    @Test
    func `failed credential write cannot advance policy hint or saved PIN`() async throws {
        let f = try await SecurityFixture()
        defer { f.clean() }
        f.store.setAccessPolicy(.none, userID: f.userID)
        f.store.setPINHint("old hint", userID: f.userID)
        f.credentials.values[.userPIN(userID: f.userID)] = "old fixture PIN"
        f.credentials.failure = .write
        #expect(throws: SecurityFailure.write) {
            try f.store.setLocalSecurity(userID: f.userID, policy: .requirePin, pin: "new", hint: "new hint")
        }
        #expect(f.store.accessPolicy(userID: f.userID) == .none && f.store.pinHint(userID: f.userID) == "old hint")
        #expect(f.credentials.values[.userPIN(userID: f.userID)] == "old fixture PIN")
        #expect(f.credentials.removals.isEmpty)
    }

    @Test
    func `both non PIN policies remove credential before installed settings writes`() async throws {
        let f = try await SecurityFixture()
        defer { f.clean() }
        for policy in [LocalUserAccessPolicy.none, .requireDeviceAuthentication] {
            f.store.setAccessPolicy(.requirePin, userID: f.userID)
            f.store.setPINHint("old hint", userID: f.userID)
            f.credentials.values[.userPIN(userID: f.userID)] = "old fixture PIN"
            f.observeCredentialBoundary()
            try f.store.setLocalSecurity(userID: f.userID, policy: policy, pin: "unused", hint: "new hint")
            #expect(f.observedPolicy == .requirePin && f.observedHint == "old hint")
            #expect(f.store.accessPolicy(userID: f.userID) == policy && f.store.pinHint(userID: f.userID) == "new hint")
            #expect(f.credentials.values[.userPIN(userID: f.userID)] == nil)
        }
        #expect(f.credentials.removals == [.userPIN(userID: f.userID), .userPIN(userID: f.userID)])
        #expect(f.credentials.writes.isEmpty && f.credentials.reads.isEmpty)
    }

    @Test
    func `failed removal retains PIN policy and hint`() async throws {
        let f = try await SecurityFixture()
        defer { f.clean() }
        f.store.setAccessPolicy(.requirePin, userID: f.userID)
        f.store.setPINHint("old hint", userID: f.userID)
        f.credentials.values[.userPIN(userID: f.userID)] = "old fixture PIN"
        f.credentials.failure = .remove
        #expect(throws: SecurityFailure.remove) {
            try f.store.setLocalSecurity(userID: f.userID, policy: .none, pin: "unused", hint: "new hint")
        }
        #expect(f.store.accessPolicy(userID: f.userID) == .requirePin && f.store.pinHint(userID: f.userID) == "old hint")
        #expect(f.credentials.values[.userPIN(userID: f.userID)] == "old fixture PIN" && f.credentials.writes.isEmpty)
    }

    @Test
    func `non PIN transition still invokes removal when no credential exists`() async throws {
        let f = try await SecurityFixture()
        defer { f.clean() }
        f.credentials.failure = .remove
        #expect(throws: SecurityFailure.remove) {
            try f.store.setLocalSecurity(userID: f.userID, policy: .none, pin: "unused", hint: "new hint")
        }
        #expect(f.credentials.removals == [.userPIN(userID: f.userID)])
        f.credentials.failure = nil
        try f.store.setLocalSecurity(userID: f.userID, policy: .none, pin: "unused", hint: "new hint")
        #expect(f.credentials.removals.count == 2 && f.store.pinHint(userID: f.userID) == "new hint")
    }

    @Test
    func `empty PIN is stored verbatim without inventing a format restriction`() async throws {
        let f = try await SecurityFixture()
        defer { f.clean() }
        try f.store.setLocalSecurity(userID: f.userID, policy: .requirePin, pin: "", hint: "")
        let matches = try f.store.matchesPIN("", userID: f.userID)
        let other = try f.store.matchesPIN("0", userID: f.userID)
        #expect(matches && !other && f.credentials.values[.userPIN(userID: f.userID)] == "")
        #expect(f.store.accessPolicy(userID: f.userID) == .requirePin && f.store.pinHint(userID: f.userID).isEmpty)
    }
}
