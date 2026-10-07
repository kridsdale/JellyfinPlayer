//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation
import JellyfinAPI
import SwiftfinNetworking

@MainActor
public enum ServerDiagnosticURLPolicy {
    /// Download authentication follows the existing SDK query-key behavior.
    /// URLs contain credentials and must never be written to diagnostic logs.
    public static func logURL(name: String, using urls: any JellyfinURLResolving) -> URL? {
        urls.url(with: Paths.getLogFile(name: name), queryAPIKey: true)
    }
}
