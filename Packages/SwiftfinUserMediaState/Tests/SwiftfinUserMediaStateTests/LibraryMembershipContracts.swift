//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import JellyfinAPI
import SwiftfinUserMediaState
import Testing

struct LibraryMembershipContracts {
    @Test
    func `missing identity cannot change membership`() {
        let data = UserItemDataDto(isPlayed: true, key: "synthetic", playbackPositionTicks: 100)
        for loaded in [false, true] {
            #expect(UserMediaStatePolicy.nextUpChange(for: data, isLoaded: loaded) == .none)
            #expect(UserMediaStatePolicy.resumeChange(for: data, isLoaded: loaded) == .none)
        }
    }

    @Test
    func `loaded next up receives the short minimum even without playback fields`() {
        #expect(UserMediaStatePolicy
            .nextUpChange(for: .init(itemID: "item", key: "synthetic"), isLoaded: true) == .refresh(minimumInterval: 3))
        #expect(UserMediaStatePolicy.nextUpChange(for: .init(itemID: "item", key: "synthetic"), isLoaded: false) == .none)
    }

    @Test
    func `played field presence includes false and precedes progress for next up`() {
        for played in [false, true] {
            #expect(UserMediaStatePolicy.nextUpChange(
                for: .init(isPlayed: played, itemID: "item", key: "synthetic", playbackPositionTicks: -1),
                isLoaded: false
            ) == .refresh(minimumInterval: 30))
        }
    }

    @Test
    func `resume removal precedes loaded and progress checks`() {
        for loaded in [false, true] {
            #expect(UserMediaStatePolicy.resumeChange(
                for: .init(isPlayed: true, itemID: "item", key: "synthetic", playbackPositionTicks: -1),
                isLoaded: loaded
            ) == .remove(itemID: "item"))
        }
    }

    @Test
    func `only unloaded positive progress refreshes resume membership`() {
        for ticks in [Int.min, -1, 0] {
            let data = UserItemDataDto(isPlayed: false, itemID: "item", key: "synthetic", playbackPositionTicks: ticks)
            #expect(UserMediaStatePolicy.resumeChange(for: data, isLoaded: false) == .none)
            #expect(UserMediaStatePolicy.nextUpChange(
                for: .init(itemID: "item", key: "synthetic", playbackPositionTicks: ticks),
                isLoaded: false
            ) == .none)
        }
        let positive = UserItemDataDto(itemID: "item", key: "synthetic", playbackPositionTicks: Int.max)
        #expect(UserMediaStatePolicy.resumeChange(for: positive, isLoaded: false) == .refresh(minimumInterval: 30))
        #expect(UserMediaStatePolicy.resumeChange(for: positive, isLoaded: true) == .none)
    }
}
