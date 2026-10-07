//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import JellyfinAPI
import SwiftfinAccountModels
import SwiftfinStorage
import SwiftfinStoredValues

/// Exact installed account/metadata addresses. Current-session and UI settings
/// remain in application composition.
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

    public static func publicInfo(serverID: String, database: SwiftfinDatabase = .shared) -> StoredValues.Key<PublicSystemInfo> {
        .init("publicInfo", ownerID: serverID, field: "publicInfo", storage: .defaults, default: .init(), database: database)
    }

    public static func userData(userID: String, database: SwiftfinDatabase = .shared) -> StoredValues.Key<UserDto> {
        .init("userData", ownerID: userID, field: "userData", storage: .sql, default: .init(), database: database)
    }
}
