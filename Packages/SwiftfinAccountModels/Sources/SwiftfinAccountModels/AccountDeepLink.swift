//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation

public struct AccountDeepLink: Equatable, Sendable {

    public enum Destination: Equatable, Sendable {
        case item(id: String)

        // The legacy library spelling routes through item resolution as well.
    }

    public let serverID: String
    public let userID: String
    public let destination: Destination

    public init?(_ url: URL) {
        guard let match = url.absoluteString.wholeMatch(
            of: /^(?:swiftfin|jellyfin):\/\/(?<serverID>[A-Za-z0-9-]+)\/(?<userID>[A-Za-z0-9-]+)\/(?<destinationType>item|library)\/(?<destinationID>[A-Za-z0-9-]+)\/?$/
        ) else { return nil }

        self.serverID = String(match.output.serverID)
        self.userID = String(match.output.userID)

        self.destination = .item(id: String(match.output.destinationID))
    }
}

public enum AccountDeepLinkError: Error, Sendable {
    case missingServer(String)
    case missingUser(String)
}
