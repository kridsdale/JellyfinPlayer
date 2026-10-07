//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import FactoryKit
import SwiftfinAccountAccess
import SwiftfinItemMetadata
import SwiftfinMediaCatalog
import SwiftfinNetworking
import SwiftfinPlaybackPreparation
import SwiftfinUserAdministration
import SwiftfinUserMediaState

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
        playbackConnection.preparation
    }

    var playbackConnection: PlaybackConnection {
        let client = self.client
        let manager = Container.shared.userSessionManager()
        return PlaybackConnection(sender: client, urls: client, userID: user.id, isCurrent: { [weak self, weak client, weak manager] in
            guard let self, let client, let manager else { return false }
            return manager.currentSession === self && self.client === client
        })
    }
}

extension UserSession {
    var mediaState: UserMediaStateClient {
        let client = self.client
        if let cached = mediaStateOwner, cached.transport === client {
            return cached.owner
        }
        let manager = Container.shared.userSessionManager()
        let executor = AuthenticatedRequestExecutor(sender: client, isCurrent: { [weak self, weak client, weak manager] in
            guard let self, let client, let manager else { return false }
            return manager.currentSession === self && self.client === client
        })
        let owner = UserMediaStateClient(executor: executor, userID: user.id)
        mediaStateOwner = (client, owner)
        return owner
    }
}

extension UserSession {
    var accountAccess: AccountAccessClient {
        let client = self.client
        let manager = Container.shared.userSessionManager()
        return AccountAccessClient(transport: client, expectedServerID: server.id, isCurrent: { [weak self, weak client, weak manager] in
            guard let self, let client, let manager else { return false }
            return manager.currentSession === self && self.client === client
        })
    }
}

extension UserSession {
    var userAdministration: UserAdministrationClient {
        let client = self.client
        let manager = Container.shared.userSessionManager()
        let executor = AuthenticatedRequestExecutor(sender: client, isCurrent: { [weak self, weak client, weak manager] in
            guard let self, let client, let manager else { return false }
            return manager.currentSession === self && self.client === client
        })
        return UserAdministrationClient(executor: executor, currentUserID: user.id)
    }
}

extension UserSession {
    /// Keep one writer across videos. A replaced transport drains its accepted
    /// predecessor before a new configuration command can be sent.
    var autoPlayConfigurationUpdates: AutoPlayConfigurationUpdates {
        let client = self.client
        if let cached = autoPlayUpdatesOwner, cached.transport === client {
            return cached.owner
        }
        let previous = autoPlayUpdatesOwner?.owner
        previous?.cancel()
        let owner = userAdministration.autoPlayUpdates(after: previous)
        autoPlayUpdatesOwner = (client, owner)
        return owner
    }
}
