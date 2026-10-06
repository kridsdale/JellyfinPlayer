//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation

public struct ServerAccountRecord: Hashable, Identifiable, Codable, Sendable {
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

public struct UserAccountRecord: Hashable, Identifiable, Codable, Sendable {
    public let id: String
    public let serverID: String
    public let username: String
    public init(id: String, serverID: String, username: String) {
        self.id = id
        self.serverID = serverID
        self.username = username
    }
}
