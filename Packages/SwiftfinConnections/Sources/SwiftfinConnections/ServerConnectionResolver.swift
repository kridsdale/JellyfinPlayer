//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation
import SwiftfinAccountModels

public enum ServerConnectionResolution: Equatable, Sendable {
    case connected(ServerConnection)
    case unreachable([ServerConnection])
}

public enum ServerConnectionProbeError: Error, Equatable, Sendable {
    case serverMismatch
}

/// The transport supplies only the reported server identity. No SDK objects,
/// account repository or application session cross this boundary.
@MainActor
public protocol ServerConnectionProbing {
    func serverID(at connection: ServerConnection, accessToken: String?) async throws -> String?
}

/// Owns ordered, interface-scoped selection and exact server-ID verification.
/// It returns a decision and never mutates saved connections or an active session.
@MainActor
public enum ServerConnectionResolver {
    public static func test(
        connection: ServerConnection,
        accessToken: String?,
        expectedServerID: String,
        probe: any ServerConnectionProbing
    ) async throws {
        try Task.checkCancellation()
        let reportedID = try await probe.serverID(at: connection, accessToken: accessToken)
        // Some SDK/native transports complete successfully after cancellation.
        // Such a result must never become a new active connection.
        try Task.checkCancellation()
        guard reportedID == expectedServerID else { throw ServerConnectionProbeError.serverMismatch }
    }

    public static func resolve(
        connections: [ServerConnection],
        accessToken: String?,
        expectedServerID: String,
        context: NetworkConnectionContext,
        probe: any ServerConnectionProbing
    ) async throws -> ServerConnectionResolution {
        try Task.checkCancellation()
        guard context.isSatisfied else { return .unreachable([]) }
        let candidates = ServerConnection.ordered(connections).filter { $0.matches(context) }
        for connection in candidates {
            do {
                try await test(connection: connection, accessToken: accessToken, expectedServerID: expectedServerID, probe: probe)
                return .connected(connection)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                try Task.checkCancellation()
            }
        }
        return .unreachable(candidates)
    }
}
