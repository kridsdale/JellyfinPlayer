//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation
import Synchronization

/// Native image-cache callbacks read this immutable-value index on any executor.
/// Settings and connection objects never enter those SDK callbacks.
final class ServerImageCacheIdentityIndex: Sendable {
    private let identities = Mutex<[URL: String]>([:])
    func replace(_ values: [URL: String]) {
        identities.withLock { $0 = values }
    }

    func serverID(for url: URL) -> String? {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        components.scheme = components.scheme?.lowercased()
        components.host = components.host?.lowercased()
        if components.path.hasSuffix("/") {
            components.path.removeLast()
        }
        let normalized = components.url ?? url
        return identities.withLock { $0[normalized] }
    }
}
