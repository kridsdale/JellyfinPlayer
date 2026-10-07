//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import FactoryKit
import SwiftfinItemMetadata
import SwiftfinNetworking

extension UserSession {
    var itemMetadata: ItemMetadataClient {
        let client = self.client
        let manager = Container.shared.userSessionManager()
        let executor = AuthenticatedRequestExecutor(sender: client, isCurrent: { [weak self, weak client, weak manager] in
            guard let self, let client, let manager else { return false }
            return manager.currentSession === self && self.client === client
        })
        return ItemMetadataClient(
            executor: executor,
            userID: user.id,
            bindingID: .init(transport: ObjectIdentifier(client), userID: user.id)
        )
    }
}
