//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import FactoryKit
import SwiftfinStorage
import SwiftfinStoredValues

typealias ServerState = SwiftfinStore.State.Server
typealias UserState = SwiftfinStore.State.User

@MainActor
enum StorageComposition {
    static func open() async throws {
        let accounts = try await SwiftfinDatabase.shared.open { userID, token in
            guard Container.shared.keychainService().set(token, forKey: "\(userID)-accessToken") else {
                throw ErrorMessage("Unable to preserve a migrated account credential")
            }
        }
        #if os(tvOS)
        if let accounts {
            StoredValues[.Server.servers] = accounts.servers
            StoredValues[.User.users] = accounts.users
        }
        #endif
        ServerImageCacheIdentity.start()
    }
}
