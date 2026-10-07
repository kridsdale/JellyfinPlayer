//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation
import JellyfinAPI

/// Pure typed-body redaction for diagnostic adapters. The host chooses its
/// replacement text; this value helper allocates no logger, transport or store.
public enum JellyfinRequestBodyRedactor {
    /// Unknown/malformed request bodies retain their original bytes. A supported
    /// DTO is re-encoded with the original SDK field/nil behavior.
    public static func body(at url: URL, body: Data, replacement: String) -> Data? {
        switch url.pathComponents.last {
        case "AuthenticateByName":
            guard var value = try? JSONDecoder().decode(AuthenticateUserByName.self, from: body) else { return body }
            value.pw = replacement
            return try? JSONEncoder().encode(value)
        case "Password":
            guard var value = try? JSONDecoder().decode(UpdateUserPassword.self, from: body) else { return body }
            value.currentPassword = replacement
            value.currentPw = replacement
            value.newPw = replacement
            value.isResetPassword = nil
            return try? JSONEncoder().encode(value)
        default: return body
        }
    }
}
