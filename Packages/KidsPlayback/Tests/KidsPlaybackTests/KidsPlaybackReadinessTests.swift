//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import KidsDiagnostics

// SPDX-License-Identifier: MPL-2.0
@testable import KidsPlayback
import Testing

private func ready(
    state: Bool = true, buffering: Bool = false, preparing: Bool = false,
    pending: Bool = false, position: Double = 0, clock: Double = 0.2, output: Int = 1
) -> Bool {
    KidsPlaybackReadiness.permitsPresentation(
        playingOrPaused: state, buffering: buffering, preparing: preparing,
        resumePending: pending, requestedPosition: position, clock: clock,
        displayedPictures: output
    )
}

@Test
func `playing without output cannot reveal the player or advance watch state`() {
    #expect(!ready(output: 0))
    #expect(!ready(state: false))
    #expect(!ready(clock: 0))
    #expect(ready())
}

@Test
func `resume readiness ignores the old or stationary clock and pending seek`() {
    #expect(!ready(position: 120, clock: 0.2))
    #expect(!ready(position: 120, clock: 120))
    #expect(!ready(pending: true, position: 120, clock: 120.3))
    #expect(ready(position: 120, clock: 120.3))
}

@Test
func `buffering and preparation retain the startup cover despite available video`() {
    #expect(!ready(buffering: true))
    #expect(!ready(preparing: true))
    #expect(ready(buffering: false, preparing: false))
}

@Test
func `nonfinite or invalid clocks and resume positions never begin playback`() {
    for clock in [Double.nan, Double.infinity, -Double.infinity, -1] {
        #expect(!ready(clock: clock))
    }
    for position in [Double.nan, Double.infinity, -1] {
        #expect(!ready(position: position))
    }
}

@Test
func `failed or recovering startup never presents partial output as successful playback`() {
    #expect(!KidsPlaybackReadiness.permitsPresentation(
        playingOrPaused: true, buffering: false, preparing: false,
        resumePending: false, failedOrRecovering: true,
        requestedPosition: 0, clock: 2, displayedPictures: 12
    ))
}
