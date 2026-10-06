//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

// SPDX-License-Identifier: MPL-2.0
import Foundation
@testable import KidsCatalog
import KidsDiagnostics
import KidsDomain
import Testing

private let cacheBinding = KidsBinding(serverID: "server", userID: "kid", showsID: "tv", moviesID: "movies")
private func cacheShow(_ id: String = "show") -> KidsItem {
    KidsItem(id: id, name: "Fixture", kind: .series, libraryID: "tv")
}

private func cacheEpisode(_ showID: String = "show") -> KidsItem {
    KidsItem(id: showID + "-episode", name: "Fixture", kind: .episode, libraryID: "tv", seriesID: showID, season: 1, episode: 1)
}

private actor CacheCounter {
    var requestCount = 0
    func fetch(_ showID: String) -> [KidsItem] {
        requestCount += 1
        return [cacheEpisode(showID)]
    }
}

private actor CacheGate {
    enum Failure: Error { case fixture }
    private(set) var requestCount = 0
    private var waiting: [Int: (String, CheckedContinuation<[KidsItem], Error>)] = [:]
    func fetch(_ showID: String) async throws -> [KidsItem] {
        requestCount += 1
        let id = requestCount
        return try await withCheckedThrowingContinuation { waiting[id] = (showID, $0) }
    }

    func wait(for total: Int) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while requestCount < total {
            if .now >= deadline {
                throw Failure.fixture
            }
            await Task.yield()
        }
    }

    func fail(_ id: Int) {
        waiting.removeValue(forKey: id)?.1.resume(throwing: Failure.fixture)
    }

    func completeAll() {
        let pending = waiting
        waiting.removeAll()
        for (_, value) in pending {
            value.1.resume(returning: [cacheEpisode(value.0)])
        }
    }
}

@Test
func `episode metadata cache rejects cross-account and nonshow access before fetching`() async throws {
    let counter = CacheCounter()
    let cache = KidsEpisodeCache(binding: cacheBinding) { await counter.fetch($0) }
    let other = KidsBinding(serverID: "server", userID: "another", showsID: "tv", moviesID: "movies")
    for (show, binding) in [(cacheShow(), other), (cacheEpisode(), cacheBinding)] {
        do {
            _ = try await cache.episodes(for: show, binding: binding)
            Issue.record("Unauthorized cache access succeeded")
        } catch { #expect(error as? KidsContractError == .denied) }
    }
    #expect(await counter.requestCount == 0)
}

@Test
func `verified episode metadata is reused and LRU capacity bounds retained shows`() async throws {
    let counter = CacheCounter()
    let cache = KidsEpisodeCache(binding: cacheBinding, capacity: 1) { await counter.fetch($0) }
    let first = try await cache.episodes(for: cacheShow(), binding: cacheBinding)
    #expect(try await cache.episodes(for: cacheShow(), binding: cacheBinding) == first)
    #expect(await counter.requestCount == 1)
    _ = try await cache.episodes(for: cacheShow("second"), binding: cacheBinding)
    _ = try await cache.episodes(for: cacheShow(), binding: cacheBinding)
    #expect(await counter.requestCount == 3)
}

@Test
func `expired episode metadata triggers a fresh verified fetch`() async throws {
    let counter = CacheCounter()
    let cache = KidsEpisodeCache(binding: cacheBinding, lifetime: .zero) { await counter.fetch($0) }
    _ = try await cache.episodes(for: cacheShow(), binding: cacheBinding)
    _ = try await cache.episodes(for: cacheShow(), binding: cacheBinding)
    #expect(await counter.requestCount == 2)
}

@Test
func `forged and ambiguous episode results never enter the cache`() async throws {
    for values in [[cacheEpisode("other")], [cacheEpisode(), cacheEpisode()]] {
        let counter = CacheCounter()
        let cache = KidsEpisodeCache(binding: cacheBinding) { id in
            _ = await counter.fetch(id)
            return values
        }
        for _ in 0 ..< 2 {
            do {
                _ = try await cache.episodes(for: cacheShow(), binding: cacheBinding)
                Issue.record("Invalid metadata was cached")
            } catch { #expect(error is KidsContractError) }
        }
        #expect(await counter.requestCount == 2)
    }
}

@Test
func `concurrent episode metadata consumers share one fetch`() async throws {
    let gate = CacheGate()
    let cache = KidsEpisodeCache(binding: cacheBinding) { try await gate.fetch($0) }
    let requests = (0 ..< 20).map { _ in Task { try await cache.episodes(for: cacheShow(), binding: cacheBinding) } }
    try await gate.wait(for: 1)
    await gate.completeAll()
    for request in requests {
        #expect(try await request.value == [cacheEpisode()])
    }
    #expect(await gate.requestCount == 1)
}

@Test
func `canceling a consumer preserves the shared fetch for other callers`() async throws {
    let gate = CacheGate()
    let cache = KidsEpisodeCache(binding: cacheBinding) { try await gate.fetch($0) }
    let canceled = Task { try await cache.episodes(for: cacheShow(), binding: cacheBinding) }
    try await gate.wait(for: 1)
    let survivor = Task { try await cache.episodes(for: cacheShow(), binding: cacheBinding) }
    canceled.cancel()
    await gate.completeAll()
    do {
        _ = try await canceled.value
        Issue.record("Canceled caller returned metadata")
    } catch { #expect(error is CancellationError) }
    #expect(try await survivor.value == [cacheEpisode()])
    #expect(try await cache.episodes(for: cacheShow(), binding: cacheBinding) == [cacheEpisode()])
    #expect(await gate.requestCount == 1)
}

@Test
func `invalidated old failures cannot remove a newer in-flight fetch`() async throws {
    let gate = CacheGate()
    let cache = KidsEpisodeCache(binding: cacheBinding) { try await gate.fetch($0) }
    let obsolete = Task { try await cache.episodes(for: cacheShow(), binding: cacheBinding) }
    try await gate.wait(for: 1)
    await cache.invalidate()
    let replacement = Task { try await cache.episodes(for: cacheShow(), binding: cacheBinding) }
    try await gate.wait(for: 2)
    await gate.fail(1)
    _ = await obsolete.result
    let joined = Task { try await cache.episodes(for: cacheShow(), binding: cacheBinding) }
    try await Task.sleep(for: .milliseconds(20))
    await gate.completeAll()
    #expect(try await replacement.value == [cacheEpisode()])
    #expect(try await joined.value == [cacheEpisode()])
    #expect(await gate.requestCount == 2)
}

@Test
func `background metadata warming skips other shows while sharing an existing fetch`() async throws {
    let gate = CacheGate()
    let cache = KidsEpisodeCache(binding: cacheBinding) { try await gate.fetch($0) }
    let first = Task { try await cache.prefetch(for: cacheShow(), binding: cacheBinding) }
    try await gate.wait(for: 1)
    #expect(try await cache.prefetch(for: cacheShow("another"), binding: cacheBinding) == nil)
    let joined = Task { try await cache.prefetch(for: cacheShow(), binding: cacheBinding) }
    // A deliberate user selection still works while speculative warming runs.
    let foreground = Task { try await cache.episodes(for: cacheShow("selected"), binding: cacheBinding) }
    try await gate.wait(for: 2)
    await gate.completeAll()
    #expect(try await first.value == [cacheEpisode()])
    #expect(try await joined.value == [cacheEpisode()])
    #expect(try await foreground.value == [cacheEpisode("selected")])
    #expect(await gate.requestCount == 2)
}
