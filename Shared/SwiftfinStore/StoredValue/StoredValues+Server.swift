//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Defaults
import FactoryKit
import Foundation
import JellyfinAPI
import SwiftfinAccountModels
import SwiftfinAccountStore
import SwiftfinStoredValues

// MARK: keys

@MainActor
extension StoredValues.Keys {

    static func ServerKey<Value: Storable>(
        _ name: String? = nil,
        ownerID: String,
        field: String,
        storage: StoredValues.Key<Value>.StorageDestination = .defaults,
        default defaultValue: Value
    ) -> Key<Value> {
        Key(
            name ?? field,
            ownerID: ownerID,
            field: field,
            storage: storage,
            default: defaultValue
        )
    }

    static func ServerKey<Value: Storable>(always: Value) -> Key<Value> {
        Key(always: always)
    }
}

// MARK: values

extension PublicSystemInfo: @retroactive Defaults.Serializable {}
extension PublicSystemInfo: @retroactive Storable {}

@MainActor
extension StoredValues.Keys {

    @MainActor
    enum Server {

        static var servers: Key<[ServerState]> {
            AccountStorageKeys.servers()
        }

        static func publicInfo(id: String) -> Key<PublicSystemInfo> {
            ServerKey(
                ownerID: id,
                field: "publicInfo",
                default: .init()
            )
        }

        static func connections(id: String) -> Key<[ServerConnection]> {
            AccountStorageKeys.connections(serverID: id)
        }

        static func activeConnectionID(id: String) -> Key<String> {
            AccountStorageKeys.activeConnectionID(serverID: id)
        }

        static func isAutoSwitchEnabled(id: String) -> Key<Bool> {
            AccountStorageKeys.autoSwitchEnabled(serverID: id)
        }
    }
}
