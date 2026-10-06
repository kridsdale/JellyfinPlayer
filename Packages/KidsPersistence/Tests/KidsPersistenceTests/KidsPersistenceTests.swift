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
import SwiftData
import Testing

private let household = KidsBinding(serverID: "server", userID: "kids", showsID: "tv", moviesID: "movies")
private func regular(_ id: String, show: String = "show") -> KidsItem {
    KidsItem(id: id, name: "Episode", kind: .episode, libraryID: "tv", seriesID: show, season: 1, episode: id == "a" ? 1 : 2)
}

@MainActor
private func device(_ writer: String, time: TimeInterval = 1000) throws -> KidsStateRepository {
    let schema = Schema([KidsCloudRow.self])
    let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
    return try KidsStateRepository(
        container: ModelContainer(for: schema, configurations: config),
        writerID: writer,
        now: { Date(timeIntervalSince1970: time) }
    )
}

/// Deliver rows through the real SwiftData SDK, emulating CloudKit transport.
/// This tests import/merge, not the external Apple service or provisioning.
@MainActor
private func deliver(_ source: KidsStateRepository, to target: KidsStateRepository) throws {
    let sourceContext = ModelContext(source.container)
    let destination = ModelContext(target.container)
    let existing = try destination.fetch(FetchDescriptor<KidsCloudRow>())
    for row in try sourceContext.fetch(FetchDescriptor<KidsCloudRow>()) {
        if let same = existing.first(where: { $0.namespace == row.namespace && $0.key == row.key && $0.writerID == row.writerID }) {
            let incoming = try JSONDecoder().decode(KidsSyncEntry.self, from: row.payload)
            let old = try JSONDecoder().decode(KidsSyncEntry.self, from: same.payload)
            if incoming.revision > old.revision {
                same.payload = row.payload
            }
        } else {
            destination.insert(KidsCloudRow(namespace: row.namespace, key: row.key, writerID: row.writerID, payload: row.payload))
        }
    }
    try destination.save()
}

@Test @MainActor
func `existing JSON migrates every field once without modifying the backup`() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let file = directory.appendingPathComponent("state-v1.json")
    var legacy = KidsState(binding: household)
    try legacy.began(item: regular("a"), mode: .ordered, showID: "show")
    legacy.checkpoint(item: regular("a"), mode: .ordered, seconds: 84)
    legacy.session?.completed = 1
    legacy.movies["film"] = KidsProgress(itemID: "film", seconds: 456)
    var bag = KidsShuffleBag()
    bag.remaining = ["b"]
    bag.last = "a"
    legacy.shuffle["show"] = bag
    legacy.preferences.spokenNavigation = true
    try KidsStateFile.save(legacy, to: file)
    let original = try Data(contentsOf: file)
    let store = try device("TV1")
    #expect(try store.load(binding: household, legacyURL: file).state == legacy)
    #expect(try Data(contentsOf: file) == original)
    let reset = try store.reset(binding: household)
    #expect(reset.state == KidsState(binding: household))
    #expect(try store.load(binding: household, legacyURL: file).state == reset.state)
}

@Test @MainActor
func `persistent SwiftData reopens with resume shuffle and session intact`() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("progress.store")
    var expected: KidsState!
    do {
        let store = try KidsStateRepository(container: KidsStateRepository.makeContainer(url: url, cloud: false), writerID: "TV")
        let baseline = try store.load(binding: household)
        var state = baseline.state
        let draw = try state.nextShuffle(showID: "show", episodes: [regular("a"), regular("b")], randomOrder: ["b", "a"])
        try state.began(item: draw, mode: .shuffle, showID: "show")
        state.checkpoint(item: draw, mode: .shuffle, seconds: 92)
        state.session?.completed = 1
        expected = try store.commit(state, since: baseline).state
    }
    let reopened = try KidsStateRepository(container: KidsStateRepository.makeContainer(url: url, cloud: false), writerID: "TV")
    #expect(try reopened.load(binding: household).state == expected)
}

@Test @MainActor
func `two TVs keep independent show and movie edits when snapshots are stale`() throws {
    let a = try device("TV1"), b = try device("TV2")
    let baseA = try a.load(binding: household), baseB = try b.load(binding: household)
    var left = baseA.state, right = baseB.state
    left.ordered["bluey"] = KidsProgress(itemID: "ep1", seconds: 23)
    right.ordered["arthur"] = KidsProgress(itemID: "ep7", seconds: 91)
    right.movies["film"] = KidsProgress(itemID: "film", seconds: 700)
    _ = try a.commit(left, since: baseA)
    try deliver(a, to: b)
    _ = try b.commit(right, since: baseB)
    try deliver(b, to: a)
    let result = try a.load(binding: household)
    #expect(result.state.ordered["bluey"]?.seconds == 23)
    #expect(result.state.ordered["arthur"]?.seconds == 91)
    #expect(result.state.movies["film"]?.seconds == 700)
    #expect(try result.state == (b.load(binding: household).state))
}

@Test @MainActor
func `offline edits converge with a deterministic same-item winner`() throws {
    let a = try device("TV1"), b = try device("TV2")
    let initialA = try a.load(binding: household), initialB = try b.load(binding: household)
    var left = initialA.state, right = initialB.state
    left.movies["film"] = KidsProgress(itemID: "film", seconds: 10)
    right.movies["film"] = KidsProgress(itemID: "film", seconds: 20)
    _ = try a.commit(left, since: initialA)
    _ = try b.commit(right, since: initialB)
    try deliver(a, to: b)
    try deliver(b, to: a)
    #expect(try a.load(binding: household).state.movies["film"]?.seconds == 20)
    #expect(try a.load(binding: household).state == b.load(binding: household).state)
}

@Test @MainActor
func `clock rollback cannot make a causal edit older than its baseline`() throws {
    let ahead = try device("ahead", time: 5000), behind = try device("behind", time: 1000)
    let base = try ahead.load(binding: household)
    var state = base.state
    state.movies["film"] = KidsProgress(itemID: "film", seconds: 200)
    _ = try ahead.commit(state, since: base)
    try deliver(ahead, to: behind)
    let baseline = try behind.load(binding: household)
    state = baseline.state
    state.movies["film"]?.seconds = 250
    _ = try behind.commit(state, since: baseline)
    try deliver(behind, to: ahead)
    #expect(try ahead.load(binding: household).state.movies["film"]?.seconds == 250)
}

@Test @MainActor
func `concurrent shuffle draws consume the union and do not move Next`() throws {
    let a = try device("TV1"), b = try device("TV2")
    let seed = try a.load(binding: household)
    var state = seed.state
    state.ordered["show"] = KidsProgress(itemID: "a", seconds: 42)
    var bag = KidsShuffleBag()
    bag.cycleID = "shared-cycle"
    bag.remaining = ["a", "b", "c"]
    state.shuffle["show"] = bag
    _ = try a.commit(state, since: seed)
    try deliver(a, to: b)
    let baseA = try a.load(binding: household), baseB = try b.load(binding: household)
    var left = baseA.state, right = baseB.state
    left.shuffle["show"]?.remaining.removeAll { $0 == "a" }
    left.shuffle["show"]?.last = "a"
    right.shuffle["show"]?.remaining.removeAll { $0 == "b" }
    right.shuffle["show"]?.last = "b"
    _ = try a.commit(left, since: baseA)
    _ = try b.commit(right, since: baseB)
    try deliver(a, to: b)
    try deliver(b, to: a)
    let combined = try a.load(binding: household)
    #expect(combined.state.shuffle["show"]?.remaining == ["c"])
    #expect(combined.state.ordered["show"] == state.ordered["show"])
    #expect(try combined.state == (b.load(binding: household).state))
}

@Test @MainActor
func `a new shuffle cycle is not emptied by old device snapshots`() throws {
    let a = try device("TV1"), b = try device("TV2")
    let base = try a.load(binding: household)
    var state = base.state
    var bag = KidsShuffleBag()
    bag.cycleID = "old"
    bag.remaining = []
    state.shuffle["show"] = bag
    _ = try a.commit(state, since: base)
    try deliver(a, to: b)
    let baseline = try b.load(binding: household)
    state = baseline.state
    _ = try state.nextShuffle(showID: "show", episodes: [regular("a"), regular("b")], randomOrder: ["a", "b"])
    _ = try b.commit(state, since: baseline)
    try deliver(b, to: a)
    #expect(try a.load(binding: household).state.shuffle["show"]?.remaining == ["a", "b"])
}

@Test @MainActor
func `reset reaches another TV and stale offline work cannot resurrect anything`() throws {
    let a = try device("TV1"), b = try device("TV2", time: 9000)
    let base = try a.load(binding: household)
    var state = base.state
    state.movies["film"] = KidsProgress(itemID: "film", seconds: 12)
    _ = try a.commit(state, since: base)
    try deliver(a, to: b)
    let stale = try b.load(binding: household)
    _ = try a.reset(binding: household)
    var offline = stale.state
    offline.ordered["late-show"] = KidsProgress(itemID: "late", seconds: 8)
    _ = try b.commit(offline, since: stale)
    try deliver(b, to: a)
    try deliver(a, to: b)
    #expect(try a.load(binding: household).state == KidsState(binding: household))
    #expect(try b.load(binding: household).state == KidsState(binding: household))
    let stopped = try b.commit(offline, since: stale, intent: .playback)
    #expect(stopped.invalidatesPlayback)
}

@Test @MainActor
func `per-show tombstones prevent old rows from restoring removed progress`() throws {
    let a = try device("TV1"), b = try device("TV2")
    let base = try a.load(binding: household)
    var state = base.state
    state.ordered["show"] = KidsProgress(itemID: "a", seconds: 87)
    state.ordered["other"] = KidsProgress(itemID: "x", seconds: 55)
    _ = try a.commit(state, since: base)
    try deliver(a, to: b)
    let baseline = try b.load(binding: household)
    state = baseline.state
    state.ordered.removeValue(forKey: "show")
    _ = try b.commit(state, since: baseline)
    try deliver(b, to: a)
    #expect(try a.load(binding: household).state.ordered["show"] == nil)
    #expect(try a.load(binding: household).state.ordered["other"]?.seconds == 55)
}

@Test @MainActor
func `a remote parent Set Next on the same episode defeats an old stream checkpoint`() throws {
    let a = try device("TV1"), b = try device("TV2")
    let base = try a.load(binding: household)
    var playing = base.state
    try playing.began(item: regular("a"), mode: .ordered, showID: "show")
    playing.checkpoint(item: regular("a"), mode: .ordered, seconds: 120)
    let active = try a.commit(playing, since: base)
    try deliver(a, to: b)
    let parentBase = try b.load(binding: household)
    var edit = parentBase.state
    try edit.setNext(regular("a"))
    _ = try b.commit(edit, since: parentBase)
    try deliver(b, to: a)
    playing = active.state
    playing.checkpoint(item: regular("a"), mode: .ordered, seconds: 130)
    let result = try a.commit(playing, since: active, intent: .playback)
    #expect(result.invalidatesPlayback)
    #expect(result.state.ordered["show"]?.seconds == 0)
    #expect(result.state.session == nil)
}

@Test @MainActor
func `remote movie Start over defeats a paused player's old checkpoint`() throws {
    let a = try device("TV1"), b = try device("TV2")
    let base = try a.load(binding: household)
    var state = base.state
    state.movies["film"] = KidsProgress(itemID: "film", seconds: 250)
    let active = try a.commit(state, since: base)
    try deliver(a, to: b)
    let parentBase = try b.load(binding: household)
    state = parentBase.state
    state.movies.removeValue(forKey: "film")
    _ = try b.commit(state, since: parentBase)
    try deliver(b, to: a)
    state = active.state
    state.movies["film"]?.seconds = 260
    let result = try a.commit(state, since: active, intent: .playback)
    #expect(result.invalidatesPlayback)
    #expect(result.state.movies["film"] == nil)
}

@Test @MainActor
func `bindings isolate users servers and approved library changes`() throws {
    let store = try device("TV")
    let base = try store.load(binding: household)
    var state = base.state
    state.movies["film"] = KidsProgress(itemID: "film", seconds: 45)
    _ = try store.commit(state, since: base)
    for changed in [
        KidsBinding(serverID: "other", userID: "kids", showsID: "tv", moviesID: "movies"),
        KidsBinding(serverID: "server", userID: "other", showsID: "tv", moviesID: "movies"),
        KidsBinding(serverID: "server", userID: "kids", showsID: "other", moviesID: "movies")
    ] {
        #expect(try store.load(binding: changed).state == KidsState(binding: changed))
        #expect(try KidsStateRepository.namespace(for: changed) != KidsStateRepository.namespace(for: household))
    }
    #expect(try store.load(binding: household).state.movies["film"]?.seconds == 45)
}

@Test @MainActor
func `damaged SwiftData payload requires parent reset and reset repairs it`() throws {
    let store = try device("TV")
    _ = try store.load(binding: household)
    let context = ModelContext(store.container)
    try context.insert(KidsCloudRow(
        namespace: KidsStateRepository.namespace(for: household),
        key: "movie/film",
        writerID: "broken",
        payload: Data("{broken".utf8)
    ))
    try context.save()
    #expect(throws: KidsContractError.invalidStateVersion) { try store.load(binding: household) }
    _ = try store.reset(binding: household)
    #expect(try store.load(binding: household).state == KidsState(binding: household))
}

@Test @MainActor
func `duplicate cloud rows converge independent of arrival order`() throws {
    let revision = KidsSyncRevision(milliseconds: 100, counter: 0, writerID: "a")
    let first = KidsSyncEntry(
        binding: household,
        key: "movie/film",
        revision: revision,
        resetID: nil,
        value: .movie(KidsProgress(itemID: "film", seconds: 10))
    )
    let second = KidsSyncEntry(
        binding: household,
        key: "movie/film",
        revision: .init(milliseconds: 100, counter: 0, writerID: "b"),
        resetID: nil,
        value: .movie(KidsProgress(itemID: "film", seconds: 20))
    )
    #expect(try KidsStateRepository.resolve([first, second, first], binding: household).state ==
        KidsStateRepository.resolve([second, first], binding: household).state)
}

@Test @MainActor
func `initial cloud import beats a later legacy JSON migration`() throws {
    let a = try device("TV1"), b = try device("TV2")
    let baseline = try a.load(binding: household)
    var current = baseline.state
    current.movies["film"] = KidsProgress(itemID: "film", seconds: 600)
    _ = try a.commit(current, since: baseline)
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let file = directory.appendingPathComponent("old.json")
    var old = KidsState(binding: household)
    old.movies["film"] = KidsProgress(itemID: "film", seconds: 10)
    _ = try b.load(binding: household) // Initial load before delayed cloud import.
    try KidsStateFile.save(old, to: file)
    try deliver(a, to: b)
    #expect(try b.load(binding: household, legacyURL: file).state.movies["film"]?.seconds == 600)
}

@Test @MainActor
func `offline preferences merge independently rather than overwriting the whole state`() throws {
    let a = try device("TV1"), b = try device("TV2")
    let baseA = try a.load(binding: household), baseB = try b.load(binding: household)
    var left = baseA.state, right = baseB.state
    left.preferences.episodeLimit = 1
    right.preferences.spokenNavigation = true
    _ = try a.commit(left, since: baseA)
    _ = try b.commit(right, since: baseB)
    try deliver(a, to: b)
    try deliver(b, to: a)
    let result = try a.load(binding: household)
    #expect(result.state.preferences.episodeLimit == 1)
    #expect(result.state.preferences.spokenNavigation)
}

@Test @MainActor
func `the SwiftData schema meets CloudKit default and uniqueness requirements`() throws {
    let schema = Schema([KidsCloudRow.self])
    let entity = try #require(schema.entities.first)
    #expect(entity.relationships.isEmpty)
    #expect(entity.attributes.count == 4)
    for attribute in entity.attributes {
        #expect(!attribute.isUnique)
        #expect(attribute.isOptional || attribute.defaultValue != nil)
    }
}

@Test @MainActor
func `late cloud delivery replaces already imported legacy progress`() throws {
    let a = try device("TV1"), b = try device("TV2")
    let baseline = try a.load(binding: household)
    var updated = baseline.state
    updated.movies["film"] = KidsProgress(itemID: "film", seconds: 600)
    _ = try a.commit(updated, since: baseline)
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let file = directory.appendingPathComponent("state-v1.json")
    var old = KidsState(binding: household)
    old.movies["film"] = KidsProgress(itemID: "film", seconds: 10)
    try KidsStateFile.save(old, to: file)
    #expect(try b.load(binding: household, legacyURL: file).state.movies["film"]?.seconds == 10)
    try deliver(a, to: b)
    #expect(try b.load(binding: household, legacyURL: file).state.movies["film"]?.seconds == 600)
}

@Test @MainActor
func `reset repairs a damaged migration receipt owned by the same installation`() throws {
    let store = try device("TV")
    _ = try store.load(binding: household)
    let context = ModelContext(store.container)
    let marker = try #require(context.fetch(FetchDescriptor<KidsCloudRow>()).first { $0.key == "migration" })
    marker.payload = Data("bad receipt".utf8)
    try context.save()
    #expect(throws: KidsContractError.invalidStateVersion) { try store.load(binding: household) }
    _ = try store.reset(binding: household)
    #expect(try store.load(binding: household).state == KidsState(binding: household))
}

@Test @MainActor
func `equal revisions with different duplicate payloads still converge`() throws {
    let revision = KidsSyncRevision(milliseconds: 100, counter: 0, writerID: "same-installation")
    let a = KidsSyncEntry(
        binding: household,
        key: "movie/film",
        revision: revision,
        resetID: nil,
        value: .movie(KidsProgress(itemID: "film", seconds: 10))
    )
    let b = KidsSyncEntry(
        binding: household,
        key: "movie/film",
        revision: revision,
        resetID: nil,
        value: .movie(KidsProgress(itemID: "film", seconds: 20))
    )
    #expect(try KidsStateRepository.resolve([a, b], binding: household).state ==
        KidsStateRepository.resolve([b, a], binding: household).state)
}

@Test @MainActor
func `a paused ordered player honors remote Set Next even without a changed clock`() throws {
    let a = try device("TV1"), b = try device("TV2")
    let base = try a.load(binding: household)
    var state = base.state
    try state.began(item: regular("a"), mode: .ordered, showID: "show")
    state.checkpoint(item: regular("a"), mode: .ordered, seconds: 100)
    let active = try a.commit(state, since: base)
    try deliver(a, to: b)
    let remoteBase = try b.load(binding: household)
    var remote = remoteBase.state
    try remote.setNext(regular("a"))
    _ = try b.commit(remote, since: remoteBase)
    try deliver(b, to: a)
    let result = try a.commit(active.state, since: active, intent: .playback, activeKey: "ordered/show")
    #expect(result.invalidatesPlayback)
    #expect(result.state.ordered["show"]?.seconds == 0)
}

@Test @MainActor
func `a paused movie honors remote Start over even without a changed clock`() throws {
    let a = try device("TV1"), b = try device("TV2")
    let base = try a.load(binding: household)
    var state = base.state
    state.movies["film"] = KidsProgress(itemID: "film", seconds: 100)
    let active = try a.commit(state, since: base)
    try deliver(a, to: b)
    let remoteBase = try b.load(binding: household)
    var remote = remoteBase.state
    remote.movies.removeValue(forKey: "film")
    _ = try b.commit(remote, since: remoteBase)
    try deliver(b, to: a)
    let result = try a.commit(active.state, since: active, intent: .playback, activeKey: "movie/film")
    #expect(result.invalidatesPlayback)
    #expect(result.state.movies["film"] == nil)
}

@Test @MainActor
func `an invalid revision cannot crash checkpointing and explicit reset repairs it`() throws {
    let store = try device("TV")
    _ = try store.load(binding: household)
    let entry = KidsSyncEntry(
        binding: household,
        key: "movie/film",
        revision: .init(milliseconds: Int64.max, counter: Int.max, writerID: "bad"),
        resetID: nil,
        value: .movie(KidsProgress(itemID: "film", seconds: 30))
    )
    let context = ModelContext(store.container)
    try context.insert(KidsCloudRow(
        namespace: KidsStateRepository.namespace(for: household),
        key: entry.key,
        writerID: "bad",
        payload: JSONEncoder().encode(entry)
    ))
    try context.save()
    #expect(throws: KidsContractError.invalidStateVersion) { try store.load(binding: household) }
    _ = try store.reset(binding: household)
    #expect(try store.load(binding: household).state == KidsState(binding: household))
}
