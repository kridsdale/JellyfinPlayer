//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation
import KidsDomain
@testable import KidsPersistence
import Testing

private let binding = KidsBinding(serverID: "server", userID: "kid", showsID: "tv", moviesID: "movies")
private func episode(_ id: String, season: Int = 1, number: Int = 1, library: String = "tv") -> KidsItem {
    KidsItem(id: id, name: id, kind: .episode, libraryID: library, seriesID: "show", season: season, episode: number)
}

private let episodes = [episode("a"), episode("b", number: 2), episode("c", season: 2)]

@Test
func `atomic persistence restores budget and isolates changed identity`() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: dir) }
    let file = dir.appendingPathComponent("state.json")
    var state = KidsState(binding: binding)
    try state.began(item: episodes[0], mode: .ordered, showID: "show")
    state.checkpoint(item: episodes[0], mode: .ordered, seconds: 87)
    _ = try state.finished(item: episodes[0], mode: .ordered, episodes: episodes)
    try KidsStateFile.save(state, to: file)
    #expect(try KidsStateFile.load(from: file, binding: binding) == state)
    let changed = KidsBinding(serverID: "new", userID: "new", showsID: "tv", moviesID: "movies")
    #expect(try KidsStateFile.load(from: file, binding: changed) == KidsState(binding: changed))
}

@Test
func `damaged local state requires deliberate parent recovery`() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let file = directory.appendingPathComponent("state.json")
    try Data("{broken".utf8).write(to: file)
    #expect(throws: KidsContractError.invalidStateVersion) { try KidsStateFile.load(from: file, binding: binding) }
    var state = KidsState(binding: binding)
    state.version = 2
    try KidsStateFile.save(state, to: file)
    #expect(throws: KidsContractError.invalidStateVersion) { try KidsStateFile.load(from: file, binding: binding) }
    try KidsStateFile.save(KidsState(binding: binding), to: file)
    #expect(try KidsStateFile.load(from: file, binding: binding) == KidsState(binding: binding))
}
