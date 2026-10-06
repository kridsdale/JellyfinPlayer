//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

// Swiftfin is subject to the Mozilla Public License, v2.0.
import Foundation
import Security
import SwiftfinCredentials
import XCTest

/// Real Security.framework interop, restricted to synthetic UUID accounts.
/// Household credentials and the actual parent PIN are never mutated here.
@MainActor
final class CredentialInteropTests: XCTestCase {
    func testExistingLegacyCredentialReadsAndUpdatesWithoutNamespaceMigration() throws {
        let userID = "kids-credential-test-" + UUID().uuidString
        let account = userID + "-accessToken"
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrAccount as String: account]
        defer { SecItemDelete(query as CFDictionary) }
        var legacyAddition = query
        legacyAddition[kSecValueData as String] = Data("synthetic-legacy".utf8)
        legacyAddition[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlocked
        XCTAssertEqual(SecItemAdd(legacyAddition as CFDictionary, nil), errSecSuccess)
        let store = KeychainCredentialStore()
        XCTAssertEqual(try store.read(.accessToken(userID: userID)), "synthetic-legacy")
        try store.write("synthetic-replacement", to: .accessToken(userID: userID))
        var legacyRead = query
        legacyRead[kSecReturnData as String] = true
        legacyRead[kSecMatchLimit as String] = kSecMatchLimitOne
        var data: CFTypeRef?
        XCTAssertEqual(SecItemCopyMatching(legacyRead as CFDictionary, &data), errSecSuccess)
        XCTAssertEqual(data as? Data, Data("synthetic-replacement".utf8))
        try store.remove(.accessToken(userID: userID))
        XCTAssertNil(try store.read(.accessToken(userID: userID)))
    }

    func testScopedUserPINDoesNotDeleteAdjacentCredential() throws {
        let userID = "kids-credential-test-" + UUID().uuidString
        let store = KeychainCredentialStore()
        defer {
            try? store.remove(.accessToken(userID: userID))
            try? store.remove(.userPIN(userID: userID))
        }
        try store.write("synthetic-token", to: .accessToken(userID: userID))
        try store.write("12345678", to: .userPIN(userID: userID))
        try store.remove(.userPIN(userID: userID))
        XCTAssertNil(try store.read(.userPIN(userID: userID)))
        XCTAssertEqual(try store.read(.accessToken(userID: userID)), "synthetic-token")
    }
}
