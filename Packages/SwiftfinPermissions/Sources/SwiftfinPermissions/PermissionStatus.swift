//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

public enum PermissionStatus: Sendable, Equatable {
    case authorized
    case denied
    case unknown
}

public enum PermissionRequestError: Error, Sendable, Equatable {
    case deviceAuthenticationUnavailable
    case unsupportedPlatform
}
