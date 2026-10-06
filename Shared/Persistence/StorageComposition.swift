//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import FactoryKit
import SwiftfinAccountModels
import SwiftfinAccountStore
import SwiftfinLocalization
import SwiftfinStorage
import SwiftfinStoredValues

typealias ServerState = ServerAccountRecord
typealias UserState = UserAccountRecord

@MainActor
enum StorageComposition {
    static func open() async throws {
        let accounts = try await SwiftfinDatabase.shared.open { userID, token in
            try Container.shared.localAccountStore().storeAccessToken(token, userID: userID)
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

// Application composition supplies the secure implementation and localized
// display name; the library resolves neither Factory nor an active session.
extension Container {
    @MainActor
    var localAccountStore: Factory<LocalAccountStore> {
        self {
            LocalAccountStore(credentials: self.keychainService(), currentURLName: L10n.currentURL)
        }.singleton
    }
}
