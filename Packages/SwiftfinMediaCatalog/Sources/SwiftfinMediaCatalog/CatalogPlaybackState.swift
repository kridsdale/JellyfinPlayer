//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation

/// Immutable catalog playback facts, independent of strings and UI frameworks.
public struct CatalogPlaybackState: Sendable, Equatable {
    public enum Phase: Sendable, Equatable {
        case live
        case unaired
        case ended
        case missing
        case rewatching
        case inProgress
        case played
        case unplayed
    }

    public let phase: Phase?
    public let remainingDuration: Duration?
    public let unplayedCount: Int?

    init(phase: Phase? = nil, remainingDuration: Duration? = nil, unplayedCount: Int? = nil) {
        self.phase = phase
        self.remainingDuration = remainingDuration
        self.unplayedCount = unplayedCount
    }
}
