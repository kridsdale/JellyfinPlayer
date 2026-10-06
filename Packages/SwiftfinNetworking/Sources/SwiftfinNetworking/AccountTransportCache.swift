//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation

/// Retains one immutable transport for an exact account/endpoint/credential
/// binding. A replaced binding gets a new client; in-flight old work retains its
/// own immutable client and cannot acquire the replacement account's token.
@MainActor
public final class AccountTransportCache: CustomStringConvertible {
    private struct Binding: Equatable {
        let url: URL
        let serverID: String
        let userID: String
        let accessToken: String
    }

    private var binding: Binding?
    private var cached: JellyfinTransport?
    private let make: @MainActor (URL, String) -> JellyfinTransport

    public init(make: @escaping @MainActor (URL, String) -> JellyfinTransport) {
        self.make = make
    }

    public func client(url: URL, serverID: String, userID: String, accessToken: String) -> JellyfinTransport {
        let next = Binding(url: url, serverID: serverID, userID: userID, accessToken: accessToken)
        if binding == next, let cached {
            return cached
        }
        let client = make(url, accessToken)
        binding = next
        cached = client
        return client
    }

    public func invalidate() {
        binding = nil
        cached = nil
    }

    public nonisolated var description: String {
        "AccountTransportCache"
    }
}
