//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

// SPDX-License-Identifier: MPL-2.0
import Foundation

/// Corrupt resume values fall back to the beginning instead of trapping during
/// Jellyfin's integer tick conversion. Ordinary finite positions retain precision.
public struct KidsPlaybackStartPosition: Equatable, Sendable {
    public let seconds: Double
    public let ticks: Int
    public init(_ position: Double) {
        let ticks = position * 10_000_000
        guard position.isFinite, position > 0, ticks.isFinite, ticks < Double(Int.max) else {
            seconds = 0
            self.ticks = 0
            return
        }
        seconds = position
        self.ticks = Int(ticks)
    }
}

/// Rejects premature native end callbacks using the installed one-second rule.
/// Missing runtime is handled by the caller's existing Stop path.
public enum PlaybackCompletionPolicy {
    public static func acceptsEnd(position: Duration, runtime: Duration) -> Bool {
        (runtime - position) <= .seconds(1)
    }
}
