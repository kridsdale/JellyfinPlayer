//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation
import Nuke
import SwiftfinImages
import Testing

@Test
func `installed poster key bytes survive alternate hosts and retain tags sizes and query order`() throws {
    let original = try #require(URL(string: "https://first.test/Items/item/Images/Primary?tag=one&maxWidth=120&maxHeight=70"))
    let alternate = try #require(URL(string: "http://alternate.test:8096/Items/item/Images/Primary?tag=one&maxWidth=120&maxHeight=70"))
    #expect(ImageCacheKeys.poster(for: original) == "4802139e5c2e6c7e92370c1f7caf7c0b7633a6a6-120")
    #expect(ImageCacheKeys.poster(for: alternate) == "4802139e5c2e6c7e92370c1f7caf7c0b7633a6a6-120")
    let resized = try #require(URL(string: "https://first.test/Items/item/Images/Primary?tag=one&maxWidth=240&maxHeight=70"))
    #expect(ImageCacheKeys.poster(for: resized) == "4802139e5c2e6c7e92370c1f7caf7c0b7633a6a6-240")
    let changed = try #require(URL(string: "https://first.test/Items/item/Images/Primary?tag=two&maxWidth=120&maxHeight=70"))
    #expect(ImageCacheKeys.poster(for: changed) != ImageCacheKeys.poster(for: original))
}

@Test
func `local splashscreen keys keep installed identity format and deny unknown endpoints`() throws {
    let index = ServerImageCacheIdentityIndex()
    let base = try #require(URL(string: "http://first.test:8096/base"))
    let alternate = try #require(URL(string: "http://alternate.test:8096/base"))
    index.replace([base: "server-A", alternate: "server-A"])
    let splash = try #require(URL(string: "http://first.test:8096/base/Branding/Splashscreen?"))
    let other = try #require(URL(string: "http://alternate.test:8096/base/Branding/Splashscreen?"))
    #expect(ImageCacheKeys.local(for: splash, identities: index) == "f71b5d548cb5dce7c8d44913300653365546079a")
    #expect(ImageCacheKeys.local(for: other, identities: index) == "f71b5d548cb5dce7c8d44913300653365546079a")
    index.replace([base: "server-B"])
    #expect(ImageCacheKeys.local(for: splash, identities: index) != "f71b5d548cb5dce7c8d44913300653365546079a")
    #expect(ImageCacheKeys.local(for: other, identities: index) == nil)
}

@Test
func `ordinary local image keys preserve poster bytes`() throws {
    let url = try #require(URL(string: "http://first.test/Items/item/Images/Primary?tag=one"))
    #expect(ImageCacheKeys.local(for: url, identities: ServerImageCacheIdentityIndex()) == ImageCacheKeys.poster(for: url))
}

@Test
func `background cache callback reads value snapshots and observes endpoint removal`() async throws {
    let index = ServerImageCacheIdentityIndex()
    let first = try #require(URL(string: "http://first.test:8096/base"))
    let removed = try #require(URL(string: "http://removed.test:8096"))
    index.replace([first: "server-A", removed: "server-B"])
    let initial = await Task.detached { [index.serverID(for: first), index.serverID(for: removed)] }.value
    #expect(initial == ["server-A", "server-B"])
    index.replace([first: "server-C"])
    let normalized = try #require(URL(string: "http://FIRST.test:8096/base/"))
    let replaced = await Task.detached { [index.serverID(for: normalized), index.serverID(for: removed)] }.value
    #expect(replaced == ["server-C", nil])
}

@Test @MainActor
func `native pipeline construction keeps installed paths cap and distinct loaders`() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    var builds = 0
    let pipelines = ImagePipelines(
        identities: ServerImageCacheIdentityIndex(),
        postersCachePath: directory.appendingPathComponent("posters", isDirectory: true),
        documentsDirectory: directory
    ) {
        builds += 1
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 20
        return DataLoader(configuration: configuration)
    }
    #expect(builds == 2 && pipelines.posters !== pipelines.local && pipelines.other !== pipelines.posters)
    let posters = try #require(pipelines.posters.configuration.dataCache as? DataCache)
    let local = try #require(pipelines.local.configuration.dataCache as? DataCache)
    #expect(posters.sizeLimit == 1024 * 1024 * 1000)
    #expect(posters.path == directory.appendingPathComponent("posters", isDirectory: true))
    #expect(local.path == directory.appendingPathComponent("Caches/org.jellyfin.swiftfin.local", isDirectory: true))
    #expect(pipelines.posters.configuration.dataLoader as? DataLoader !== pipelines.local.configuration.dataLoader as? DataLoader)
}

@Test @MainActor
func `cache invalidation removes an exact image and preserves other cached data`() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let pipelines = ImagePipelines(
        identities: ServerImageCacheIdentityIndex(),
        postersCachePath: directory.appendingPathComponent("posters", isDirectory: true),
        documentsDirectory: directory
    ) { DataLoader(configuration: .ephemeral) }
    let firstURL = try #require(URL(string: "https://first.test/Items/a/Images/Primary?tag=one"))
    let first = ImageRequest(url: firstURL)
    let otherURL = try #require(URL(string: "https://first.test/Items/b/Images/Primary?tag=two"))
    let other = ImageRequest(url: otherURL)
    pipelines.posters.cache.storeCachedData(Data([1, 2, 3]), for: first)
    pipelines.posters.cache.storeCachedData(Data([4, 5]), for: other)
    #expect(pipelines.posters.cache.cachedData(for: first) == Data([1, 2, 3]))
    try await pipelines.posters.removeItem(for: #require(first.url))
    #expect(pipelines.posters.cache.cachedData(for: first) == nil)
    #expect(pipelines.posters.cache.cachedData(for: other) == Data([4, 5]))
}

@Test @MainActor
func `cancelled fallback cannot begin an image load`() async throws {
    let pipeline = ImagePipeline(configuration: .withURLCache)
    let url = try #require(URL(string: "https://no-request.test/image"))
    let source = ImageSource(url: url)
    let task = Task { await pipeline.loadFirstImage(from: [source]) }
    task.cancel()
    #expect(await task.value == nil)
}
