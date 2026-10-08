//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation

public enum ServerConnectionDraftError: Error, Sendable {
    case invalidURL
    case invalidWifiName
}

/// Editable connection values; preserves the installed normalization rules.
/// No transport, native network/permission query, or persistence dependency.
public struct ServerConnectionDraft: Equatable, Sendable {
    public let id: String
    public var name: String
    public var urlString: String
    public var interface: ServerConnection.Interface
    public var wifiSSIDs: [String]
    public var priority: Int
    public var useWifiName: Bool

    public init(connection: ServerConnection) {
        self.id = connection.id
        self.name = connection.name
        self.urlString = connection.url.absoluteString
        self.interface = connection.interface
        self.wifiSSIDs = connection.wifiSSIDs
        self.priority = connection.priority
        self.useWifiName = connection.interface == .wifi && !connection.wifiSSIDs.isEmpty
    }

    public var url: URL? {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolved = urlString.contains("://") ? trimmed : "http://" + trimmed
        return URL(string: resolved).flatMap(ServerConnection.normalizedURL)
    }

    public func connection() throws -> ServerConnection {
        guard let url, url.host != nil else { throw ServerConnectionDraftError.invalidURL }
        let normalizedSSIDs = wifiSSIDs.compactMap { value -> String? in
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }.sorted()
        if interface == .wifi, useWifiName, normalizedSSIDs.isEmpty {
            throw ServerConnectionDraftError.invalidWifiName
        }
        return ServerConnection(
            id: id,
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            url: url,
            interface: interface,
            wifiSSIDs: interface == .wifi && useWifiName ? normalizedSSIDs : [],
            priority: priority
        )
    }
}
