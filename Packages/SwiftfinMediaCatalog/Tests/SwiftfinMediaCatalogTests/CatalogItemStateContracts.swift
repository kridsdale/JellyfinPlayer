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

struct CatalogItemStateContracts {
    private let now = Date(timeIntervalSince1970: 100)
    @Test
    func `item airing includes end instant and aired begins strictly after it`() {
        let item = BaseItemDto(endDate: .init(timeIntervalSince1970: 100), startDate: .init(timeIntervalSince1970: 40))
        let state = CatalogItemState(item, at: now)
        #expect(state.isAiring && !state.hasAired && !state.isUnaired && state.progressPercentage == 1)
        let after = CatalogItemState(item, at: now.addingTimeInterval(0.1))
        #expect(!after.isAiring && after.hasAired)
    }

    @Test
    func `nested program controls airing recording and percentage but not parent duration`() {
        let child = BaseItemDto(endDate: .init(timeIntervalSince1970: 110), startDate: .init(timeIntervalSince1970: 90), timerID: "child")
        let parent = BaseItemDto(
            currentProgram: child,
            endDate: .init(timeIntervalSince1970: 40),
            startDate: .init(timeIntervalSince1970: 120)
        )
        let state = CatalogItemState(parent, at: now)
        #expect(state.isAiring && state.isRecording && state.progressPercentage == 0.5)
        #expect(state.programDuration == -80 && state.programProgress == 0.25)
        #expect(state.programProgress(relativeTo: .init(timeIntervalSince1970: 125)) == -0.0625)
    }

    @Test
    func `zero span retains raw nonfinite ratio but no airing percentage`() {
        let item = BaseItemDto(endDate: now, startDate: now, userData: .init(key: "synthetic", playedPercentage: 30))
        let state = CatalogItemState(item, at: now)
        #expect(state.programProgress?.isNaN == true && state.programDuration == 0)
        #expect(state.progressPercentage == nil)
        #expect(state.programProgress(relativeTo: now.addingTimeInterval(1))?.isInfinite == true)
    }

    @Test
    func `premiere is fallback only and absent dates preserve nil progress`() {
        let item = BaseItemDto(premiereDate: now.addingTimeInterval(10), userData: .init(key: "synthetic", playedPercentage: 120))
        let state = CatalogItemState(item, at: now)
        #expect(state.isUnaired && !state.hasAired && !state.isAiring)
        #expect(state.programDuration == nil && state.programProgress == nil && state.progressPercentage == 1.2)
        var withStart = item
        withStart.startDate = now.addingTimeInterval(-1)
        #expect(!CatalogItemState(withStart, at: now).isUnaired)
    }

    @Test
    func `tick duration preserves truncation signed resume and missing runtime`() {
        var item = BaseItemDto(runTimeTicks: 750_009, userData: .init(key: "synthetic", playbackPositionTicks: -11))
        #expect(CatalogItemState(item, at: now).runtime == .microseconds(75000))
        #expect(CatalogItemState(item, at: now).startSeconds == .microseconds(-1))
        item.runTimeTicks = 0
        #expect(CatalogItemState(item, at: now).runtime == nil)
        item.userData?.playbackPositionTicks = Int.min
        #expect(CatalogItemState(item, at: now).startSeconds == .microseconds(Int64(Int.min) / 10))
    }

    @Test
    func `type playback button and direct playable content are distinct`() {
        var item = BaseItemDto(parentID: "parent", seriesID: "series", seriesName: "Show", type: .series)
        let series = CatalogItemState(item, at: now)
        #expect(!series.isPlayable && series.presentsPlayButton(permitted: true) && !series.presentsPlayButton(permitted: false))
        item.type = .episode
        #expect(CatalogItemState(item, at: now).parentRootID == "series" && CatalogItemState(item, at: now).parentTitle == "Show")
        item.locationType = .virtual
        #expect(!CatalogItemState(item, at: now).isPlayable)
        item.type = nil
        item.locationType = nil
        #expect(CatalogItemState(item, at: now).isPlayable && !CatalogItemState(item, at: now).presentsPlayButton(permitted: true))
    }
}
