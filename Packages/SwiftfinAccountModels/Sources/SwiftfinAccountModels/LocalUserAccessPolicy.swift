//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import SwiftfinLocalization

public enum LocalUserAccessPolicy: String, CaseIterable, Codable, Sendable {

    case none
    case requireDeviceAuthentication
    case requirePin

    public var displayTitle: String {
        switch self {
        case .none:
            L10n.none
        case .requireDeviceAuthentication:
            L10n.deviceAuth
        case .requirePin:
            L10n.pin
        }
    }

    public func createReason(user: UserAccountRecord) -> String? {
        switch self {
        case .none: nil
        case .requireDeviceAuthentication:
            L10n.requireDeviceAuthForUser(user.username)
        case .requirePin:
            L10n.createPinForUser(user.username)
        }
    }

    public func authenticateReason(user: UserAccountRecord) -> String? {
        switch self {
        case .none: nil
        case .requireDeviceAuthentication:
            L10n.requireDeviceAuthForUser(user.username)
        case .requirePin:
            L10n.enterPinForUser(user.username)
        }
    }
}
