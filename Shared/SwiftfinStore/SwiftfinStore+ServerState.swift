//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import FactoryKit
import Foundation
import JellyfinAPI
import Pulse
import SwiftfinAccountModels
import SwiftfinAccountStore
import SwiftfinNetworking
import SwiftfinStoredValues

@MainActor
extension ServerState {
    /// - Note: Since this is created from a server, it does not
    ///         have a user access token.
    @MainActor
    var client: JellyfinTransport {
        JellyfinTransport.swiftfin(url: effectiveServerURL)
    }
}

@MainActor
extension ServerState {

    var activeServerConnection: ServerConnection? {
        get { Container.shared.localAccountStore().activeConnection(for: self) }
        nonmutating set { Container.shared.localAccountStore().setActiveConnection(newValue, serverID: id) }
    }

    /// Deletes the model that this state represents and
    /// all settings from `StoredValues`.
    func delete() throws {
        try Container.shared.localAccountStore().deleteServer(self)
    }

    var effectiveServerURL: URL {
        Container.shared.localAccountStore().effectiveURL(for: self)
    }

    func ensureServerConnections() -> [ServerConnection] {
        Container.shared.localAccountStore().ensureConnections(for: self)
    }

    @MainActor
    func getPublicSystemInfo() async throws -> PublicSystemInfo {

        let request = Paths.getPublicSystemInfo
        let response = try await client.send(request)

        return response.value
    }

    func hasServerConnection(url: URL) -> Bool {
        Container.shared.localAccountStore().hasConnection(url: url, server: self)
    }

    var isAutoSwitchEnabled: Bool {
        get { Container.shared.localAccountStore().autoSwitchEnabled(serverID: id) }
        nonmutating set { Container.shared.localAccountStore().setAutoSwitchEnabled(newValue, serverID: id) }
    }

    @MainActor
    var isVersionCompatible: Bool {
        let publicInfo = StoredValues[.Server.publicInfo(id: self.id)]

        if let version = publicInfo.version {
            return JellyfinClient.Version(stringLiteral: version).majorMinor >= client.version.majorMinor
        } else {
            return false
        }
    }

    var serverConnections: [ServerConnection] {
        get { Container.shared.localAccountStore().connections(for: self) }
        nonmutating set { Container.shared.localAccountStore().setConnections(newValue, serverID: id) }
    }

    @MainActor
    var splashScreenImageSource: ImageSource {
        ImageSource(url: client.url(with: Paths.getSplashscreen()))
    }

    @MainActor
    func updateServerInfo() async throws {
        let servers = StoredValues[.Server.servers]
        guard let currentServer = servers.first(where: { $0.id == id }) else { return }

        let publicInfo = try await getPublicSystemInfo()
        let updatedName = publicInfo.serverName ?? currentServer.name

        let updatedServer = ServerState(
            urls: currentServer.urls,
            currentURL: currentServer.currentURL,
            name: updatedName,
            id: currentServer.id,
            userIDs: currentServer.userIDs
        )

        StoredValues[.Server.servers] = servers.map { $0.id == id ? updatedServer : $0 }
        StoredValues[.Server.publicInfo(id: currentServer.id)] = publicInfo
    }
}
