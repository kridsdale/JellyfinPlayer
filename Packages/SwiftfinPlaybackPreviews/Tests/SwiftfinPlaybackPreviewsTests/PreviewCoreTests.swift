//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation
import SwiftfinPlaybackPreviews
import Testing

@MainActor
private final class Loader {
    var requests: [Int] = []
    private var pending: [Int: [CheckedContinuation<Int?, Never>]] = [:]
    private var starts: [Int: [CheckedContinuation<Void, Never>]] = [:]
    func load(_ index: Int) async -> Int? {
        requests.append(index)
        return await withCheckedContinuation { continuation in
            pending[index, default: []].append(continuation)
            for waiter in starts.removeValue(forKey: index) ?? [] {
                waiter.resume()
            }
        }
    }

    func started(_ index: Int) async {
        if pending[index] != nil {
            return
        }
        await withCheckedContinuation { starts[index, default: []].append($0) }
    }

    func finish(_ index: Int, _ value: Int?) {
        for continuation in pending.removeValue(forKey: index) ?? [] {
            continuation.resume(returning: value)
        }
    }

    func finishAll() {
        for index in Array(pending.keys) {
            finish(index, nil)
        }
    }
}

@Test
func `chapter timeline includes last chapter and retains source indexes`() {
    let chapters = [
        PreviewChapter(start: nil, url: nil),
        PreviewChapter(start: .zero, url: nil),
        PreviewChapter(start: .seconds(10), url: nil)
    ]
    #expect(ChapterPreviewTimeline.index(for: .seconds(-1), chapters: chapters) == 1)
    #expect(ChapterPreviewTimeline.index(for: .seconds(9), chapters: chapters) == 1)
    #expect(ChapterPreviewTimeline.index(for: .seconds(10), chapters: chapters) == 2)
    #expect(ChapterPreviewTimeline.index(for: .seconds(999), chapters: chapters) == 2)
    #expect(ChapterPreviewTimeline.index(for: .zero, chapters: []) == nil)
    #expect(ChapterPreviewTimeline.index(for: .zero, chapters: [.init(start: nil, url: nil)]) == nil)
}

@Test
func `sprite timeline has half open sheets and valid last frame`() throws {
    let layout = try #require(TrickplayPreviewLayout(columns: 2, rows: 2, width: 320, intervalMilliseconds: 1000, runtime: .seconds(8)))
    #expect(layout.address(for: .seconds(-1)) == .init(sheet: 0, tile: 0, interval: 0))
    #expect(layout.address(for: .seconds(3.999)) == .init(sheet: 0, tile: 3, interval: 3))
    #expect(layout.address(for: .seconds(4)) == .init(sheet: 1, tile: 0, interval: 4))
    #expect(layout.address(for: .seconds(8)) == .init(sheet: 1, tile: 3, interval: 7))
    #expect(layout.address(for: .seconds(500)) == layout.address(for: .seconds(8)))
    #expect(try layout.adjacentSheets(to: #require(layout.address(for: .zero))) == [1])
    #expect(try layout.adjacentSheets(to: #require(layout.address(for: .seconds(8)))) == [0])
}

@Test
func `invalid and overflowing sprite configuration is rejected`() {
    for (columns, rows, width, interval, runtime) in [
        (0, 2, 320, 1000, 8),
        (-1, 2, 320, 1000, 8),
        (2, 0, 320, 1000, 8),
        (2, 2, 0, 1000, 8),
        (2, 2, 320, 0, 8),
        (2, 2, 320, -1, 8),
        (2, 2, 320, 1000, 0),
        (
            Int.max,
            2,
            320,
            1000,
            8
        )
    ] {
        #expect(TrickplayPreviewLayout(
            columns: columns,
            rows: rows,
            width: width,
            intervalMilliseconds: interval,
            runtime: .seconds(runtime)
        ) == nil)
    }
}

@Test
func `extreme timeline does not trap integer conversion`() throws {
    let layout = try #require(TrickplayPreviewLayout(columns: 1, rows: 1, width: 1, intervalMilliseconds: 1, runtime: .seconds(Int.max)))
    #expect(layout.address(for: .seconds(Int.max)) == nil)
}

@Test
func `chapter descriptions exclude urls and tokens`() {
    let chapter = PreviewChapter(start: .zero, url: URL(string: "https://localhost.invalid/image?api_key=synthetic"))
    #expect(!String(describing: chapter).contains("localhost"))
    #expect(!String(reflecting: chapter).contains("api_key"))
}

@Test @MainActor
func `concurrent preview requests share one load and reuse image`() async {
    let loader = Loader(), cache = PreviewImageCache<Int>(isCurrent: { true }, load: loader.load)
    let first = Task { await cache.image(at: 0) }, second = Task { await cache.image(at: 0) }
    await loader.started(0)
    loader.finish(0, 42)
    let a = await first.value, b = await second.value, c = await cache.image(at: 0)
    #expect(a == 42 && b == 42 && c == 42)
    #expect(loader.requests == [0])
}

@Test @MainActor
func `failed preview loads remain retryable`() async {
    var attempts = 0
    let cache = PreviewImageCache<Int>(isCurrent: { true }) { _ in attempts += 1
        return attempts == 1 ? nil : 42
    }
    let first = await cache.image(at: 0), second = await cache.image(at: 0)
    #expect(first == nil)
    #expect(second == 42)
    #expect(attempts == 2)
}

@Test @MainActor
func `invalidation drops late noncooperating load and prevents more io`() async {
    let loader = Loader(), cache = PreviewImageCache<Int>(isCurrent: { true }, load: loader.load)
    let pending = Task { await cache.image(at: 0) }
    await loader.started(0)
    cache.invalidate()
    loader.finish(0, 42)
    let result = await pending.value, next = await cache.image(at: 1)
    #expect(result == nil && next == nil)
    #expect(loader.requests == [0])
    #expect(!cache.isValid)
}

@Test @MainActor
func `identity replacement drops late and cached images`() async {
    var current = true
    let loader = Loader(), cache = PreviewImageCache<Int>(isCurrent: { current }, load: loader.load)
    let pending = Task { await cache.image(at: 0) }
    await loader.started(0)
    current = false
    loader.finish(0, 42)
    let result = await pending.value
    #expect(result == nil)
    #expect(!cache.isValid)
    current = true
    let later = await cache.image(at: 0)
    #expect(later == nil)
    #expect(loader.requests == [0])
}

@Test @MainActor
func `image retention uses bounded least recently used policy`() async {
    var requests: [Int] = []
    let cache = PreviewImageCache<Int>(capacity: 2, isCurrent: { true }) { index in requests.append(index)
        return index
    }
    _ = await cache.image(at: 0)
    _ = await cache.image(at: 1)
    _ = await cache.image(at: 0)
    _ = await cache.image(at: 2)
    _ = await cache.image(at: 0)
    _ = await cache.image(at: 1)
    #expect(requests == [0, 1, 2, 1])
}

@Test @MainActor
func `bounded warmup cannot displace required load and latest request can`() async {
    let loader = Loader(), cache = PreviewImageCache<Int>(flightLimit: 2, isCurrent: { true }, load: loader.load)
    cache.prefetch([0, 1, 2])
    await loader.started(0)
    await loader.started(1)
    #expect(loader.requests.sorted() == [0, 1])
    let latest = Task { await cache.image(at: 3) }
    await loader.started(3)
    loader.finish(0, 100)
    loader.finish(3, 300)
    let result = await latest.value
    #expect(result == 300)
    #expect(loader.requests.sorted() == [0, 1, 3])
    loader.finishAll()
    cache.invalidate()
}

@Test @MainActor
func `canceled waiter does not cancel shared image load`() async {
    let loader = Loader(), cache = PreviewImageCache<Int>(isCurrent: { true }, load: loader.load)
    let canceled = Task { await cache.image(at: 0) }
    await loader.started(0)
    canceled.cancel()
    loader.finish(0, 42)
    let discarded = await canceled.value, retained = await cache.image(at: 0)
    #expect(discarded == nil)
    #expect(retained == 42)
    #expect(loader.requests == [0])
}

@Test @MainActor
func `owner can release with pending warmup`() async {
    let loader = Loader()
    var cache: PreviewImageCache<Int>? = PreviewImageCache(isCurrent: { true }, load: loader.load)
    weak let weakCache = cache
    cache?.prefetch([0])
    await loader.started(0)
    cache = nil
    #expect(weakCache == nil)
    loader.finishAll()
}

@Test @MainActor
func `negative and already canceled requests perform no load`() async {
    var requests = 0
    let cache = PreviewImageCache<Int>(isCurrent: { true }) { _ in requests += 1
        return 1
    }
    let negative = await cache.image(at: -1)
    let canceled = Task { () -> Int? in
        withUnsafeCurrentTask { $0?.cancel() }
        return await cache.image(at: 0)
    }
    let result = await canceled.value
    #expect(negative == nil && result == nil)
    #expect(requests == 0)
}
