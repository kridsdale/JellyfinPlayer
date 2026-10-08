//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation
import SwiftfinAccountModels

public enum UserAdmissionMode: Sendable {
    case new
    case existing(replaceAccessToken: Bool)
}

/// Opaque local admission receipt, prepared before an authentication suspension.
/// Contains no token, PIN, hint or native authentication result.
public struct UserAdmissionSnapshot: Sendable {
    let owner: ObjectIdentifier
    let user: UserAccountRecord
    let mode: UserAdmissionMode
    let existing: UserAccountRecord?
    let endpoint: URL
    let policy: LocalUserAccessPolicy
}
