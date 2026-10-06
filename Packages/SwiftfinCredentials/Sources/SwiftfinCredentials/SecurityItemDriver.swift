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
protocol SecurityItemDriving: AnyObject {
    func copy(_ query: [String: Any]) -> (status: Int32, data: Data?)
    func update(_ query: [String: Any], attributes: [String: Any]) -> Int32
    func add(_ query: [String: Any]) -> Int32
    func delete(_ query: [String: Any]) -> Int32
}

@MainActor
final class NativeSecurityItemDriver: SecurityItemDriving {
    func copy(_ query: [String: Any]) -> (status: Int32, data: Data?) {
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        return (status, result as? Data)
    }

    func update(_ query: [String: Any], attributes: [String: Any]) -> Int32 {
        SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
    }

    func add(_ query: [String: Any]) -> Int32 {
        SecItemAdd(query as CFDictionary, nil)
    }

    func delete(_ query: [String: Any]) -> Int32 {
        SecItemDelete(query as CFDictionary)
    }
}
