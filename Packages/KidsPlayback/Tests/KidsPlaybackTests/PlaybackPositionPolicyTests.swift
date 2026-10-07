//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

// SPDX-License-Identifier: MPL-2.0
import Foundation
import KidsPlayback
import Testing

@Test
func `finite resume positions retain seconds and truncated Jellyfin ticks`() {
    let position = KidsPlaybackStartPosition(1.23456789)
    #expect(position.seconds == 1.23456789 && position.ticks == 12_345_678)
}

@Test
func `invalid negative zero and overflowing resume positions restart safely`() {
    for value in [-1.0, 0, -Double.infinity, Double.infinity, Double.nan, Double.greatestFiniteMagnitude, Double(Int.max) / 10_000_000] {
        #expect(KidsPlaybackStartPosition(value) == KidsPlaybackStartPosition(0))
    }
}

@Test
func `largest safely representable resume tick remains finite and positive`() {
    let value = (Double(Int.max) / 10_000_000).nextDown
    let position = KidsPlaybackStartPosition(value)
    #expect(position.seconds == value && position.ticks > 0 && position.ticks < Int.max)
}

@Test
func `completion preserves early boundary exact end and overrun semantics`() {
    #expect(!PlaybackCompletionPolicy.acceptsEnd(position: .seconds(98.999), runtime: .seconds(100)))
    #expect(PlaybackCompletionPolicy.acceptsEnd(position: .seconds(99), runtime: .seconds(100)))
    #expect(PlaybackCompletionPolicy.acceptsEnd(position: .seconds(100), runtime: .seconds(100)))
    #expect(PlaybackCompletionPolicy.acceptsEnd(position: .seconds(101), runtime: .seconds(100)))
}
