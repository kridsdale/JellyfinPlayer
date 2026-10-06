//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import FactoryKit
import SwiftfinAccountModels
import SwiftfinCredentials
import SwiftfinStorage
import SwiftfinStoredValues

typealias ServerState = ServerAccountRecord
typealias UserState = UserAccountRecord

@MainActor
enum StorageComposition {
    static func open() async throws {
        let accounts = try await SwiftfinDatabase.shared.open { userID, token in
            try Container.shared.keychainService().write(token, to: .accessToken(userID: userID))
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
