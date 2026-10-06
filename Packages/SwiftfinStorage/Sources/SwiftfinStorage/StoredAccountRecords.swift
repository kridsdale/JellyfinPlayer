//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation

/// Codable records carried by the inherited database migration, without account services.
public enum SwiftfinStore {
    enum V1 {}
    enum V2 {}
    enum V3 {}
    public enum State {
        public struct Server: Hashable, Identifiable, Codable, Sendable {
            public let urls: Set<URL>
            public let currentURL: URL
            public let name: String
            public let id: String
            public let userIDs: [String]
            public init(urls: Set<URL>, currentURL: URL, name: String, id: String, userIDs: [String]) {
                self.urls = urls
                self.currentURL = currentURL
                self.name = name
                self.id = id
                self.userIDs = userIDs
            }
        }

        public struct User: Hashable, Identifiable, Codable, Sendable {
            public let id: String
            public let serverID: String
            public let username: String
            public init(id: String, serverID: String, username: String) {
                self.id = id
                self.serverID = serverID
                self.username = username
            }
        }
    }
}

typealias AnyStoredData = SwiftfinStore.V3.AnyData
typealias ServerState = SwiftfinStore.State.Server
typealias UserState = SwiftfinStore.State.User
