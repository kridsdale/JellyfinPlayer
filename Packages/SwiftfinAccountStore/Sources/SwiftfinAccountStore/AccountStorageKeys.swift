//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import SwiftfinAccountModels
import SwiftfinStorage
import SwiftfinStoredValues

/// Exact installed-account addresses. SDK metadata and current-session/UI
/// settings remain with their owners, rather than expanding this inventory.
@MainActor
public enum AccountStorageKeys {
    public static func servers(ownerID: String = "swiftfinApp", database: SwiftfinDatabase = .shared) -> StoredValues
    .Key<[ServerAccountRecord]> {
        .init("servers", ownerID: ownerID, field: "servers", storage: .sql, default: [], database: database)
    }

    public static func users(ownerID: String = "swiftfinApp", database: SwiftfinDatabase = .shared) -> StoredValues
    .Key<[UserAccountRecord]> {
        .init("users", ownerID: ownerID, field: "users", storage: .sql, default: [], database: database)
    }

    public static func connections(serverID: String, database: SwiftfinDatabase = .shared) -> StoredValues.Key<[ServerConnection]> {
        .init("serverConnections", ownerID: serverID, field: "serverConnections", storage: .defaults, default: [], database: database)
    }

    public static func activeConnectionID(serverID: String, database: SwiftfinDatabase = .shared) -> StoredValues.Key<String> {
        .init(
            "activeServerConnectionID",
            ownerID: serverID,
            field: "activeServerConnectionID",
            storage: .defaults,
            default: "",
            database: database
        )
    }

    public static func autoSwitchEnabled(serverID: String, database: SwiftfinDatabase = .shared) -> StoredValues.Key<Bool> {
        .init(
            "isAutoSwitchEnabled",
            ownerID: serverID,
            field: "isAutoSwitchEnabled",
            storage: .defaults,
            default: false,
            database: database
        )
    }

    public static func accessPolicy(userID: String, database: SwiftfinDatabase = .shared) -> StoredValues.Key<LocalUserAccessPolicy> {
        .init("accessPolicy", ownerID: userID, field: "accessPolicy", storage: .sql, default: .none, database: database)
    }

    public static func pinHint(userID: String, database: SwiftfinDatabase = .shared) -> StoredValues.Key<String> {
        .init("pinHint", ownerID: userID, field: "pinHint", storage: .sql, default: "", database: database)
    }
}
