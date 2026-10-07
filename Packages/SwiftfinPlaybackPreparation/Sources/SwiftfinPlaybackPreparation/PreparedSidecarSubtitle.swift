//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation

/// An immutable subtitle URL resolved for one prepared item. Native players
/// receive this value instead of consulting a mutable application session.
public struct PreparedSidecarSubtitle: Equatable, Sendable {
    public let jellyfinIndex: Int?
    public let url: URL
}
