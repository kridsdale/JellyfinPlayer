//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Combine
import Foundation
import SwiftfinAccountModels
import SwiftfinImages
import SwiftfinStoredValues
import SwiftfinText

@MainActor
enum ServerImageCacheIdentity {
    nonisolated static let index = ServerImageCacheIdentityIndex()
    private static var servers: StoredValueObservation<[ServerState]>?
    private static var connections: [String: StoredValueObservation<[ServerConnection]>] = [:]
    private static var serverSubscription: AnyCancellable?
    private static var connectionSubscriptions: [String: AnyCancellable] = [:]

    nonisolated static func serverID(for url: URL) -> String? {
        index.serverID(for: url)
    }

    static func start() {
        guard servers == nil else { refresh()
            return
        }
        let owner = StoredValueObservation(StoredValues.Keys.Server.servers)
        servers = owner
        serverSubscription = owner.objectWillChange.sink {
            Task { @MainActor in rebuildConnectionObservers()
                refresh()
            }
        }
        rebuildConnectionObservers()
        refresh()
    }

    private static func rebuildConnectionObservers() {
        guard let servers else { return }
        let existing = connections
        let existingSubscriptions = connectionSubscriptions
        var next: [String: StoredValueObservation<[ServerConnection]>] = [:]
        var nextSubscriptions: [String: AnyCancellable] = [:]
        for server in servers.value where next[server.id] == nil {
            if let owner = existing[server.id] {
                next[server.id] = owner
                nextSubscriptions[server.id] = existingSubscriptions[server.id]
            } else {
                let owner = StoredValueObservation(StoredValues.Keys.Server.connections(id: server.id))
                next[server.id] = owner
                nextSubscriptions[server.id] = owner.objectWillChange.sink { Task { @MainActor in refresh() } }
            }
        }
        connections = next
        connectionSubscriptions = nextSubscriptions
    }

    private static func refresh() {
        var values: [URL: String] = [:]
        for server in servers?.value ?? [] {
            for connection in server.serverConnections where values[connection.url] == nil {
                values[connection.url] = server.id
            }
        }
        index.replace(values)
    }
}
