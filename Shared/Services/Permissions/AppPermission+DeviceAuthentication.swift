//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

#if os(iOS)
import SwiftfinLocalization
import SwiftfinPermissions

extension AppPermission {
    static let deviceAuthentication = AppPermission(
        id: "device-authentication",
        displayTitle: L10n.deviceAuth,
        privacyDescriptionKey: "NSFaceIDUsageDescription",
        canRequest: { DeviceAuthenticationPermission.canRequest },
        request: { reason in
            do { return try await DeviceAuthenticationPermission.request(reason: reason ?? "") }
            catch PermissionRequestError.deviceAuthenticationUnavailable { throw ErrorMessage(L10n.deviceAuthFailed) }
        },
        status: { DeviceAuthenticationPermission.status }
    )
}
#endif
