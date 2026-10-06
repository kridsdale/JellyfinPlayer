//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

// SPDX-License-Identifier: MPL-2.0
import Foundation

public enum KidsAPIError: Error, LocalizedError, Equatable {
    case authentication
    case policy
    case libraryChanged
    case unavailable
    case connection
    case invalidResponse
    public var errorDescription: String? {
        switch self {
        case .authentication: "A grown-up needs to sign in again."
        case .policy: "Use an account with access only to Kid TV and Kid Movies, without administration or deletion."
        case .libraryChanged: "The approved libraries have changed. A grown-up needs to check setup."
        case .unavailable: "This video is unavailable."
        case .connection: "We cannot reach your TV library right now."
        case .invalidResponse: "The library needs a grown-up to check it."
        }
    }
}
