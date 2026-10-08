//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation
import SwiftfinLocalization

public struct ServerConnection: Hashable, Identifiable, Codable, Sendable {

    public enum Interface: String, CaseIterable, Codable, Sendable {
        case any
        case wifi
        case cellular

        public var displayTitle: String {
            switch self {
            case .any:
                L10n.any
            case .wifi:
                L10n.wifi
            case .cellular:
                L10n.cellular
            }
        }
    }

    public enum TestState: Equatable, Sendable {
        case idle
        case testing
        case success
        case failure(String)
    }

    public let id: String
    public var name: String
    public private(set) var url: URL
    public private(set) var interface: Interface
    public private(set) var wifiSSIDs: [String]
    public var priority: Int

    public init(
        id: String,
        name: String,
        url: URL,
        interface: Interface,
        wifiSSIDs: [String] = [],
        priority: Int
    ) {
        self.id = id
        self.name = name
        self.url = url
        self.interface = interface
        self.wifiSSIDs = wifiSSIDs
        self.priority = priority
    }

    /// Retains the installed connection identity normalization: lowercase scheme
    /// and host and remove one trailing path slash; keep port, query and base path.
    public static func normalizedURL(_ url: URL) -> URL? {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        components.scheme = components.scheme?.lowercased()
        components.host = components.host?.lowercased()
        if !components.path.isEmpty, components.path.hasSuffix("/") {
            components.path.removeLast()
        }
        return components.url
    }

    public var displayTitle: String {
        {
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? url.absoluteString : trimmed
        }()
    }

    public func matches(_ context: NetworkConnectionContext) -> Bool {
        switch interface {
        case .any:
            return context.isSatisfied
        case .wifi:
            guard context.interface == .wifi else { return false }
            guard !wifiSSIDs.isEmpty else { return true }
            return wifiSSIDs.contains {
                $0.caseInsensitiveCompare(context.wifiSSID ?? "") == .orderedSame
            }
        case .cellular:
            return context.interface == .cellular
        }
    }

    private var ssidKey: Set<String> {
        Set(wifiSSIDs.map(\.localizedLowercase))
    }

    public static func isDuplicate(_ connection: ServerConnection, in connections: [ServerConnection]) -> Bool {
        connections.contains { existingConnection in
            existingConnection.id != connection.id &&
                existingConnection.url == connection.url &&
                existingConnection.interface == connection.interface &&
                existingConnection.ssidKey == connection.ssidKey
        }
    }

    public static func ordered(_ connections: [ServerConnection], preservingOrder: Bool = false) -> [ServerConnection] {
        let connections = preservingOrder ? connections : connections.sorted { $0.priority < $1.priority }

        return connections
            .enumerated()
            .map { index, connection in
                connection.with(priority: index)
            }
    }

    public func with(priority: Int) -> ServerConnection {
        ServerConnection(
            id: id,
            name: name,
            url: url,
            interface: interface,
            wifiSSIDs: wifiSSIDs,
            priority: priority
        )
    }
}
