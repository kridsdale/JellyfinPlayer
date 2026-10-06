//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

// SPDX-License-Identifier: MPL-2.0
import Foundation
@testable import KidsArtwork
import KidsCatalog
import KidsDiagnostics
import KidsDomain
import Testing

private let artBinding = KidsBinding(serverID: "server", userID: "kid", showsID: "tv", moviesID: "movies")
private func artItem(_ id: String = "show", tag: String = "art") -> KidsItem {
    KidsItem(id: id, name: "Fixture", kind: .series, libraryID: "tv", imageTag: tag, imageOwnerID: id)
}

private actor ArtCounter {
    private(set) var requestCount = 0
    func fetch(_ item: KidsItem, _ width: Int) -> Data {
        requestCount += 1
        return Data(repeating: UInt8(width % 256), count: 8)
    }
}

private actor ArtGate {
    enum Failure: Error { case fixture }
    private(set) var requestCount = 0
    private(set) var peakActive = 0
    private var pending: [Int: CheckedContinuation<Data, Error>] = [:]
    func fetch() async throws -> Data {
        requestCount += 1
        let id = requestCount
        return try await withCheckedThrowingContinuation {
            pending[id] = $0
            peakActive = max(peakActive, pending.count)
        }
    }

    func wait(for requests: Int) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while requestCount < requests {
            if .now >= deadline {
                throw Failure.fixture
            }
            await Task.yield()
        }
    }

    func fail(_ id: Int) {
        pending.removeValue(forKey: id)?.resume(throwing: Failure.fixture)
    }

    func completeAll() {
        let saved = pending
        pending.removeAll()
        for continuation in saved.values {
            continuation.resume(returning: Data([1, 2, 3]))
        }
    }
}

@Test
func `art cache rejects other bindings and forged image owners even on a hit`() async throws {
    let counter = ArtCounter()
    let cache = KidsArtworkCache(binding: artBinding) { await counter.fetch($0, $1) }
    _ = try await cache.data(for: artItem(), binding: artBinding)
    var other = artBinding
    other.userID = "another"
    var forged = artItem("another")
    forged.imageOwnerID = "show"
    var wrongLibrary = artItem()
    wrongLibrary.libraryID = "adult"
    for (item, binding) in [(artItem(), other), (forged, artBinding), (wrongLibrary, artBinding)] {
        do {
            _ = try await cache.data(for: item, binding: binding)
            Issue.record("Unauthorized image cache access")
        } catch { #expect(error as? KidsContractError == .denied) }
    }
    #expect(await counter.requestCount == 1)
}

@Test
func `art cache keys include owner tag and requested size`() async throws {
    let counter = ArtCounter()
    let cache = KidsArtworkCache(binding: artBinding) { await counter.fetch($0, $1) }
    let first = try await cache.data(for: artItem(), binding: artBinding)
    #expect(try await cache.data(for: artItem(), binding: artBinding) == first)
    _ = try await cache.data(for: artItem(tag: "new"), binding: artBinding)
    _ = try await cache.data(for: artItem(), binding: artBinding, width: 800)
    _ = try await cache.data(for: artItem("other"), binding: artBinding)
    #expect(await counter.requestCount == 4)
}

@Test
func `expired or oversized artwork is fetched again and byte capacity evicts LRU`() async throws {
    let counter = ArtCounter()
    let expired = KidsArtworkCache(binding: artBinding, lifetime: .zero) { await counter.fetch($0, $1) }
    for _ in 0 ..< 2 {
        _ = try await expired.data(for: artItem(), binding: artBinding)
    }
    #expect(await counter.requestCount == 2)
    let cache = KidsArtworkCache(binding: artBinding, byteLimit: 8) { await counter.fetch($0, $1) }
    _ = try await cache.data(for: artItem(), binding: artBinding)
    _ = try await cache.data(for: artItem("second"), binding: artBinding)
    _ = try await cache.data(for: artItem(), binding: artBinding)
    #expect(await counter.requestCount == 5)
    let oversized = KidsArtworkCache(binding: artBinding, byteLimit: 7) { await counter.fetch($0, $1) }
    for _ in 0 ..< 2 {
        _ = try await oversized.data(for: artItem(), binding: artBinding)
    }
    #expect(await counter.requestCount == 7)
}

@Test
func `concurrent art consumers share a request and cancellation preserves surviving consumers`() async throws {
    let gate = ArtGate()
    let cache = KidsArtworkCache(binding: artBinding) { _, _ in try await gate.fetch() }
    let canceled = Task { try await cache.data(for: artItem(), binding: artBinding) }
    try await gate.wait(for: 1)
    let survivors = (0 ..< 12).map { _ in Task { try await cache.data(for: artItem(), binding: artBinding) } }
    canceled.cancel()
    await gate.completeAll()
    do { _ = try await canceled.value
        Issue.record("Canceled caller returned cached data")
    } catch { #expect(error is CancellationError) }
    for survivor in survivors {
        #expect(try await survivor.value == Data([1, 2, 3]))
    }
    #expect(await gate.requestCount == 1)
}

@Test
func `art requests are limited to four even across different owners`() async throws {
    let gate = ArtGate()
    let cache = KidsArtworkCache(binding: artBinding) { _, _ in try await gate.fetch() }
    let requests = (0 ..< 12).map { index in
        Task { try await cache.data(for: artItem("show-\(index)"), binding: artBinding) }
    }
    for total in [4, 8, 12] {
        try await gate.wait(for: total)
        #expect(await gate.peakActive <= 4)
        await gate.completeAll()
    }
    for request in requests {
        #expect(try await request.value == Data([1, 2, 3]))
    }
}

@Test
func `art invalidation cannot let old failures clear a replacement flight`() async throws {
    let gate = ArtGate()
    let cache = KidsArtworkCache(binding: artBinding) { _, _ in try await gate.fetch() }
    let old = Task { try await cache.data(for: artItem(), binding: artBinding) }
    try await gate.wait(for: 1)
    await cache.invalidate()
    let replacement = Task { try await cache.data(for: artItem(), binding: artBinding) }
    try await gate.wait(for: 2)
    await gate.fail(1)
    _ = await old.result
    let joined = Task { try await cache.data(for: artItem(), binding: artBinding) }
    try await Task.sleep(for: .milliseconds(20))
    await gate.completeAll()
    #expect(try await replacement.value == Data([1, 2, 3]))
    #expect(try await joined.value == Data([1, 2, 3]))
    #expect(await gate.requestCount == 2)
}

@Test
func `a failed image fetch is retriable rather than cached`() async throws {
    let gate = ArtGate()
    let cache = KidsArtworkCache(binding: artBinding) { _, _ in try await gate.fetch() }
    let first = Task { try await cache.data(for: artItem(), binding: artBinding) }
    try await gate.wait(for: 1)
    await gate.fail(1)
    _ = await first.result
    let second = Task { try await cache.data(for: artItem(), binding: artBinding) }
    try await gate.wait(for: 2)
    await gate.completeAll()
    #expect(try await second.value == Data([1, 2, 3]))
    #expect(await gate.requestCount == 2)
}

@Test
func `memory pressure drops completed art while leaving future requests authorized`() async throws {
    let counter = ArtCounter()
    let cache = KidsArtworkCache(binding: artBinding) { await counter.fetch($0, $1) }
    _ = try await cache.data(for: artItem(), binding: artBinding)
    await cache.trimForMemoryPressure()
    _ = try await cache.data(for: artItem(), binding: artBinding)
    _ = try await cache.data(for: artItem(), binding: artBinding)
    #expect(await counter.requestCount == 2)
    var other = artBinding
    other.userID = "another"
    do {
        _ = try await cache.data(for: artItem(), binding: other)
        Issue.record("Trimming weakened binding authorization")
    } catch { #expect(error as? KidsContractError == .denied) }
}

@Test
func `pre-warning shared loads complete without refilling the art cache`() async throws {
    let gate = ArtGate()
    let cache = KidsArtworkCache(binding: artBinding) { _, _ in try await gate.fetch() }
    let visible = Task { try await cache.data(for: artItem(), binding: artBinding) }
    try await gate.wait(for: 1)
    await cache.trimForMemoryPressure()
    await gate.completeAll()
    #expect(try await visible.value == Data([1, 2, 3]))
    let afterWarning = Task { try await cache.data(for: artItem(), binding: artBinding) }
    try await gate.wait(for: 2)
    await gate.completeAll()
    #expect(try await afterWarning.value == Data([1, 2, 3]))
    #expect(try await cache.data(for: artItem(), binding: artBinding) == Data([1, 2, 3]))
    #expect(await gate.requestCount == 2)
}
