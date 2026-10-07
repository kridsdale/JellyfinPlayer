//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import FactoryKit
import SwiftfinItemMetadata
import SwiftfinMediaCatalog
import SwiftfinNetworking
import SwiftfinPlaybackPreparation

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

extension UserSession {
    var mediaCatalog: MediaCatalogClient {
        let client = self.client
        let manager = Container.shared.userSessionManager()
        return MediaCatalogClient(reader: client, userID: user.id, isCurrent: { [weak self, weak client, weak manager] in
            guard let self, let client, let manager else { return false }
            return manager.currentSession === self && self.client === client
        })
    }
}

extension UserSession {
    var playbackPreparation: PlaybackPreparationClient {
        let client = self.client
        let manager = Container.shared.userSessionManager()
        let executor = AuthenticatedRequestExecutor(sender: client, isCurrent: { [weak self, weak client, weak manager] in
            guard let self, let client, let manager else { return false }
            return manager.currentSession === self && self.client === client
        })
        return PlaybackPreparationClient(executor: executor, urls: client, userID: user.id)
    }
}
