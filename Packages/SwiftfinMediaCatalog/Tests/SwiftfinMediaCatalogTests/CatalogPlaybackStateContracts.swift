//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation
import JellyfinAPI
import SwiftfinMediaCatalog
import SwiftfinTime
import Testing

struct CatalogPlaybackStateContracts {
    private let now = Date(timeIntervalSince1970: 100)

    @Test
    func `nested current program owns the interval instead of parent resume data`() {
        let child = BaseItemDto(runTimeTicks: 800_000_000, userData: .init(key: "fixture", playbackPositionTicks: 500_000_000))
        let parent = BaseItemDto(
            currentProgram: .init(currentProgram: child),
            runTimeTicks: 100_000_000,
            userData: .init(key: "fixture", playbackPositionTicks: 10_000_000)
        )
        #expect(CatalogItemState(parent, at: now).progressLabelInterval == 30)
    }

    @Test
    func `resumed media preserves whole seconds signed intervals and priority over airing`() {
        var item = BaseItemDto(
            endDate: now.addingTimeInterval(30),
            runTimeTicks: 120_999_999,
            startDate: now.addingTimeInterval(-90),
            userData: .init(key: "fixture", playbackPositionTicks: 20_000_000)
        )
        #expect(CatalogItemState(item, at: now).progressLabelInterval == 10)
        item.runTimeTicks = 30_000_000
        item.userData?.playbackPositionTicks = 20_000_001
        #expect(CatalogItemState(item, at: now).progressLabelInterval == 0)
        item.runTimeTicks = 10_000_001
        item.userData?.playbackPositionTicks = 20_000_000
        #expect(CatalogItemState(item, at: now).progressLabelInterval == 0)
        item.runTimeTicks = 1_000_000
        item.userData?.playbackPositionTicks = 31_000_000
        #expect(CatalogItemState(item, at: now).progressLabelInterval == -3)
    }

    @Test
    func `airing fallback uses one captured clock and includes the exact end instant`() {
        var item = BaseItemDto(
            endDate: now,
            runTimeTicks: 40_000_000,
            startDate: now.addingTimeInterval(-10),
            userData: .init(key: "fixture", playbackPositionTicks: 0)
        )
        #expect(CatalogItemState(item, at: now).progressLabelInterval == 10)
        #expect(CatalogItemState(item, at: now.addingTimeInterval(0.1)).progressLabelInterval == nil)
        item.runTimeTicks = 0
        item.userData?.playbackPositionTicks = 20_000_000
        #expect(CatalogItemState(item, at: now).progressLabelInterval == 10)
        #expect(CatalogItemState(BaseItemDto(), at: now).progressLabelInterval == nil)
    }

    @Test
    func `malformed opposite tick extremes cannot overflow the label projection`() {
        var item = BaseItemDto(runTimeTicks: Int.max, userData: .init(key: "fixture", playbackPositionTicks: -1))
        #expect(CatalogItemState(item, at: now).progressLabelInterval == nil)
        item.runTimeTicks = Int.min
        item.userData?.playbackPositionTicks = 1
        #expect(CatalogItemState(item, at: now).progressLabelInterval == nil)
        item.userData?.playbackPositionTicks = Int.min
        #expect(CatalogItemState(item, at: now).progressLabelInterval == 0)
    }

    @Test
    func `spoken live state distinguishes remaining duration from the elapsed visual label`() {
        let item = BaseItemDto(endDate: now.addingTimeInterval(20), startDate: now.addingTimeInterval(-10), type: .program)
        let state = CatalogItemState(item, at: now)
        let spoken = state.playbackState(canBePlayed: false)
        #expect(spoken.phase == .live && spoken.remainingDuration == .seconds(20) && spoken.unplayedCount == nil)
        #expect(state.progressLabelInterval == 10)
        #expect(CatalogItemState(item, at: now.addingTimeInterval(20)).playbackState(canBePlayed: false).remainingDuration == .zero)
        #expect(CatalogItemState(item, at: now.addingTimeInterval(21)).playbackState(canBePlayed: false).phase == .ended)
        #expect(CatalogItemState(item, at: now.addingTimeInterval(-11)).playbackState(canBePlayed: false).phase == .unaired)
        #expect(CatalogItemState(BaseItemDto(channelType: .tv), at: now).playbackState(canBePlayed: false).phase == .live)
    }

    @Test
    func `rewatch progress unknown counts and invalid percentages retain their precedence`() {
        var item = BaseItemDto(
            runTimeTicks: 10_000_001,
            type: .episode,
            userData: .init(isPlayed: true, key: "fixture", playbackPositionTicks: 10_000_000, unplayedItemCount: 2)
        )
        var state = CatalogItemState(item, at: now).playbackState(canBePlayed: true)
        #expect(state.phase == .rewatching && state.remainingDuration == .zero && state.unplayedCount == nil)
        item.userData?.isPlayed = false
        item.userData?.playbackPositionTicks = 20_000_000
        state = CatalogItemState(item, at: now).playbackState(canBePlayed: true)
        #expect(state.phase == .inProgress && state.remainingDuration == .zero && state.unplayedCount == 2)
        item.userData?.playbackPositionTicks = -9
        item.userData?.playedPercentage = .infinity
        #expect(CatalogItemState(item, at: now).playbackState(canBePlayed: true).phase == .unplayed)
        item.userData?.isPlayed = nil
        item.userData?.playedPercentage = .nan
        #expect(CatalogItemState(item, at: now).playbackState(canBePlayed: true).phase == nil)
        item.userData?.playedPercentage = 3
        state = CatalogItemState(item, at: now).playbackState(canBePlayed: true)
        #expect(state.phase == .inProgress && state.remainingDuration == nil && state.unplayedCount == 2)
    }

    @Test
    func `eligibility denial keeps future and missing states but suppresses media progress`() async {
        var item = BaseItemDto(
            locationType: .virtual,
            premiereDate: now.addingTimeInterval(1),
            userData: .init(isPlayed: false, key: "fixture", playbackPositionTicks: 10, unplayedItemCount: 4)
        )
        #expect(CatalogItemState(item, at: now).playbackState(canBePlayed: false).phase == .unaired)
        item.premiereDate = nil
        #expect(CatalogItemState(item, at: now).playbackState(canBePlayed: false).phase == .missing)
        item.locationType = nil
        let captured = CatalogItemState(item, at: now)
        let denied = await Task.detached { captured.playbackState(canBePlayed: false) }.value
        #expect(denied.phase == nil && denied.remainingDuration == nil && denied.unplayedCount == nil)
        item.userData?.isPlayed = true
        item.userData?.playbackPositionTicks = 0
        #expect(CatalogItemState(item, at: now).playbackState(canBePlayed: true).phase == .played)
    }
}
