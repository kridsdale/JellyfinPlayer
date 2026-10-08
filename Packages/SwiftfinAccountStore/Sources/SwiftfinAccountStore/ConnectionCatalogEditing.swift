//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation
import SwiftfinAccountModels

/// Exact local settings submitted with a connection probe. No credential is retained.
public struct ConnectionCatalogSnapshot: Sendable {
    let owner: ObjectIdentifier
    public let server: ServerAccountRecord
    public let connections: [ServerConnection]
    public let active: ServerConnection?
    public let autoSwitchEnabled: Bool
}

public enum ConnectionCatalogEdit: Sendable {
    case upsert(ServerConnection)
    case delete(String)
    case activate(ServerConnection)
    case reorder([String])
}

public extension LocalAccountStore {
    func connectionCatalog(serverID: String) throws -> ConnectionCatalogSnapshot {
        try Task.checkCancellation()
        guard let server = servers.first(where: { $0.id == serverID }) else { throw AccountStoreError.identityMismatch }
        let connections = ensureConnections(for: server)
        try Task.checkCancellation()
        return .init(
            owner: ObjectIdentifier(self),
            server: server,
            connections: connections,
            active: activeConnection(for: server),
            autoSwitchEnabled: autoSwitchEnabled(serverID: serverID)
        )
    }

    func validateConnectionCatalog(_ snapshot: ConnectionCatalogSnapshot) throws {
        try Task.checkCancellation()
        guard snapshot.owner == ObjectIdentifier(self), servers.first(where: { $0.id == snapshot.server.id }) == snapshot.server,
              connections(for: snapshot.server) == snapshot.connections,
              activeConnection(for: snapshot.server) == snapshot.active,
              autoSwitchEnabled(serverID: snapshot.server.id) == snapshot.autoSwitchEnabled
        else { throw CancellationError() }
    }

    /// Validated edits retain installed IDs and priority order. Deleting the active
    /// or last connection is a no-op. A delayed probe never overwrites newer settings.
    @discardableResult
    func editConnections(
        _ edit: ConnectionCatalogEdit,
        snapshot: ConnectionCatalogSnapshot,
        validate: Checkpoint = {}
    ) throws -> ConnectionCatalogSnapshot {
        var expected = snapshot
        func check() throws {
            try validate()
            try validateConnectionCatalog(expected)
        }
        try check()
        var connections = snapshot.connections
        var active = snapshot.active
        var writesCatalog = true
        switch edit {
        case let .upsert(connection):
            guard !connection.id.isEmpty, connection.url.host != nil,
                  !ServerConnection.isDuplicate(connection, in: connections) else { throw AccountStoreError.invalidConnection }
            if let index = connections.firstIndex(where: { $0.id == connection.id }) {
                connections[index] = connection
            } else {
                connections.append(connection)
            }
        case let .delete(id):
            guard connections.count > 1, active?.id != id else { return snapshot }
            connections.removeAll { $0.id == id }
        case let .activate(connection):
            guard connections.contains(connection) else { throw AccountStoreError.invalidConnection }
            active = connection
            writesCatalog = false
        case let .reorder(ids):
            guard ids.count == connections.count, Set(ids).count == ids.count,
                  Set(ids) == Set(connections.map(\.id)) else { throw AccountStoreError.invalidConnection }
            let byID = Dictionary(uniqueKeysWithValues: connections.map { ($0.id, $0) })
            connections = ids.compactMap { byID[$0] }
        }
        if writesCatalog {
            connections = ServerConnection.ordered(connections, preservingOrder: true)
            if let id = active?.id {
                active = connections.first { $0.id == id }
            }
            expected = .init(
                owner: ObjectIdentifier(self),
                server: snapshot.server,
                connections: connections,
                active: active,
                autoSwitchEnabled: snapshot.autoSwitchEnabled
            )
            try checkBeforeWrite(snapshot, validate: validate)
            setConnections(connections, serverID: snapshot.server.id)
        } else {
            expected = .init(
                owner: ObjectIdentifier(self),
                server: snapshot.server,
                connections: connections,
                active: active,
                autoSwitchEnabled: snapshot.autoSwitchEnabled
            )
            try checkBeforeWrite(snapshot, validate: validate)
            setActiveConnection(active, serverID: snapshot.server.id)
        }
        try check()
        return expected
    }

    private func checkBeforeWrite(_ snapshot: ConnectionCatalogSnapshot, validate: Checkpoint) throws {
        try validate()
        try validateConnectionCatalog(snapshot)
    }
}
