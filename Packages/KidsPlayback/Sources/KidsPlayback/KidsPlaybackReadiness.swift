//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

// SPDX-License-Identifier: MPL-2.0
import Foundation
import KidsDiagnostics

/// Readiness requires a decoded output and a clock beyond the requested resume
/// point. A playing state or an allocated video surface alone is insufficient.
public enum KidsPlaybackReadiness {
    public static func permitsPresentation(
        playingOrPaused: Bool,
        buffering: Bool,
        preparing: Bool,
        resumePending: Bool,
        failedOrRecovering: Bool = false,
        requestedPosition: Double,
        clock: Double,
        displayedPictures: Int
    ) -> Bool {
        guard playingOrPaused, !buffering, !preparing, !resumePending, !failedOrRecovering,
              requestedPosition.isFinite, requestedPosition >= 0,
              clock.isFinite, clock > requestedPosition + 0.1,
              displayedPictures > 0 else { return false }
        return true
    }
}
