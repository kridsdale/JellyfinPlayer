//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import JellyfinAPI
import SwiftfinServerOperations
import Testing

struct PlaybackSessionSelectionContracts {
    @Test
    func `matching device item is preferred without reordering the input`() {
        let first = SessionInfoDto(deviceID: "a", id: "first", nowPlayingItem: .init(id: "other"))
        let match = SessionInfoDto(deviceID: "a", id: "match", nowPlayingItem: .init(id: "target"))
        let foreign = SessionInfoDto(deviceID: "b", id: "foreign", nowPlayingItem: .init(id: "target"))
        let values = [foreign, first, match]
        #expect(ServerOperationsPolicy.playbackSession(in: values, deviceID: "a", itemID: "target") == match)
        #expect(values.map(\.id) == ["foreign", "first", "match"])
    }

    @Test
    func `fallback is the first same-device payload`() {
        let first = SessionInfoDto(deviceID: "a", id: "first")
        let later = SessionInfoDto(deviceID: "a", id: "later", nowPlayingItem: .init(id: "other"))
        #expect(ServerOperationsPolicy.playbackSession(in: [first, later], deviceID: "a", itemID: "target") == first)
        #expect(ServerOperationsPolicy.playbackSession(in: [first], deviceID: "b", itemID: "target") == nil)
        #expect(ServerOperationsPolicy.playbackSession(in: [], deviceID: nil, itemID: "target") == nil)
    }

    @Test
    func `missing device ids match only missing device ids`() {
        let known = SessionInfoDto(deviceID: "a", id: "known", nowPlayingItem: .init(id: "target"))
        let unknown = SessionInfoDto(id: "unknown")
        #expect(ServerOperationsPolicy.playbackSession(in: [known, unknown], deviceID: nil, itemID: "target") == unknown)
        #expect(ServerOperationsPolicy.playbackSession(in: [known], deviceID: nil, itemID: "target") == nil)
    }

    @Test
    func `duplicate item matches preserve the complete first payload`() {
        let first = SessionInfoDto(deviceID: "a", id: nil, nowPlayingItem: .init(id: "target", name: "First payload"))
        let later = SessionInfoDto(deviceID: "a", id: nil, nowPlayingItem: .init(id: "target", name: "Later payload"))
        #expect(ServerOperationsPolicy.playbackSession(in: [first, later], deviceID: "a", itemID: "target") == first)
    }
}
