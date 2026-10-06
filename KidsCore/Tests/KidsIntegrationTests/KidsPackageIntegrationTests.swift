//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

// SPDX-License-Identifier: MPL-2.0
import Foundation
import KidsDomain
import KidsPersistence
import KidsPlayback
import Testing

@Test @MainActor
func `extracted modules preserve durable resume and the persistent model identity`() throws {
    #expect(String(reflecting: KidsCloudRow.self) == "KidsPersistence.KidsCloudRow")
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("progress.store")
    let binding = KidsBinding(serverID: "server", userID: "child", showsID: "tv", moviesID: "movies")
    let item = KidsItem(id: "episode", name: "Fixture", kind: .episode, libraryID: "tv", seriesID: "show", season: 1, episode: 1)
    do {
        let store = try KidsStateRepository(container: KidsStateRepository.makeContainer(url: url, cloud: false), writerID: "TV-A")
        let baseline = try store.load(binding: binding)
        var state = baseline.state
        try state.began(item: item, mode: .ordered, showID: "show")
        state.checkpoint(item: item, mode: .ordered, seconds: 113)
        try store.commit(state, since: baseline, intent: .playback, activeKey: "ordered/show")
    }
    let reopened = try KidsStateRepository(container: KidsStateRepository.makeContainer(url: url, cloud: false), writerID: "TV-A")
    let state = try reopened.load(binding: binding).state
    #expect(try state.orderedNext(showID: "show", episodes: [item]).1 == 113)
    #expect(!KidsPlaybackReadiness.permitsPresentation(
        playingOrPaused: true,
        buffering: false,
        preparing: false,
        resumePending: false,
        requestedPosition: 113,
        clock: 0,
        displayedPictures: 1
    ))
    #expect(KidsPlaybackReadiness.permitsPresentation(
        playingOrPaused: true,
        buffering: false,
        preparing: false,
        resumePending: false,
        requestedPosition: 113,
        clock: 114,
        displayedPictures: 1
    ))
}
