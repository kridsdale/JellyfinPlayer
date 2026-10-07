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
    static let location = AppPermission(
        id: "location",
        displayTitle: L10n.location,
        privacyDescriptionKey: "NSLocationWhenInUseUsageDescription",
        canRequest: { LocationPermission.canRequest },
        request: { _ in try await LocationPermission.request() },
        status: { LocationPermission.status }
    )
}
#endif
