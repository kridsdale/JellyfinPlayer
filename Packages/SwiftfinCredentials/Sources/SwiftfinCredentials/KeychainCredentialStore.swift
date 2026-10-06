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

@MainActor
public final class KeychainCredentialStore: CredentialStore {
    private let driver: any SecurityItemDriving
    public convenience init() {
        self.init(driver: NativeSecurityItemDriver())
    }

    init(driver: any SecurityItemDriving) {
        self.driver = driver
    }

    /// Same class/account-only scope as the prior default KeychainSwift client.
    /// No new service, prefix, access group or synchronization attribute.
    private func query(for key: CredentialKey) throws -> [String: Any] {
        try [kSecClass as String: kSecClassGenericPassword, kSecAttrAccount as String: key.account]
    }

    public func read(_ key: CredentialKey) throws -> String? {
        var query = try query(for: key)
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        query[kSecReturnData as String] = true
        let result = driver.copy(query)
        if result.status == errSecItemNotFound {
            return nil
        }
        guard result.status == errSecSuccess else { throw CredentialStoreError.system(operation: .read, status: result.status) }
        guard let data = result.data, let value = String(data: data, encoding: .utf8) else { throw CredentialStoreError.invalidEncoding }
        return value
    }

    public func write(_ value: String, to key: CredentialKey) throws {
        let query = try query(for: key)
        let attributes: [String: Any] = [
            kSecValueData as String: Data(value.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked
        ]
        // Preserve an existing credential if replacement fails. The former
        // helper deleted first, then attempted an add.
        var status = driver.update(query, attributes: attributes)
        if status == errSecItemNotFound {
            var addition = query
            addition.merge(attributes) { _, new in new }
            status = driver.add(addition)
            if status == errSecDuplicateItem {
                // Another legitimate writer inserted this exact account.
                // One bounded update, without deleting either credential.
                status = driver.update(query, attributes: attributes)
            }
        }
        guard status == errSecSuccess else { throw CredentialStoreError.system(operation: .write, status: status) }
    }

    public func remove(_ key: CredentialKey) throws {
        let status = try driver.delete(query(for: key))
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw CredentialStoreError.system(operation: .remove, status: status)
        }
    }
}
