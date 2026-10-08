//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation
import Nuke

/// Owns the native image pipelines and disk-cache policies. Nuke values are exposed
/// only for explicit integration with Nuke UI; settings and logging stay in composition.
@MainActor
public final class ImagePipelines {
    public let posters: ImagePipeline
    public let local: ImagePipeline
    public let other: ImagePipeline

    public init(
        identities: ServerImageCacheIdentityIndex,
        postersCachePath: URL? = nil,
        documentsDirectory: URL? = nil,
        makeDataLoader: @MainActor () -> DataLoader
    ) {
        let posterFilename: DataCache.FilenameGenerator = { name in
            URL(string: name).flatMap { ImageCacheKeys.poster(for: $0) }
        }
        let posterCache: DataCache? = if let postersCachePath {
            try? DataCache(path: postersCachePath, filenameGenerator: posterFilename)
        } else {
            try? DataCache(name: "org.jellyfin.swiftfin/Posters", filenameGenerator: posterFilename)
        }
        posterCache?.sizeLimit = 1024 * 1024 * 1000
        let root = documentsDirectory ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        let localCache = root.flatMap { root in
            try? DataCache(path: root.appendingPathComponent("Caches/org.jellyfin.swiftfin.local", isDirectory: true)) { name in
                URL(string: name).flatMap { ImageCacheKeys.local(for: $0, identities: identities) }
            }
        }
        let posterLoader = makeDataLoader()
        let localLoader = makeDataLoader()
        posters = ImagePipeline(delegate: CacheDelegate()) { config in
            config.dataCache = posterCache
            config.dataLoader = posterLoader
        }
        local = ImagePipeline(delegate: CacheDelegate()) { config in
            config.dataCache = localCache
            config.dataLoader = localLoader
        }
        other = ImagePipeline(configuration: .withURLCache)
    }
}

private final class CacheDelegate: ImagePipeline.Delegate {
    func cacheKey(for request: ImageRequest, pipeline: ImagePipeline) -> String? {
        request.url.flatMap { ImageCacheKeys.poster(for: $0) }
    }
}

public extension ImagePipeline {
    func loadFirstImage(from requests: some Collection<ImageSource>) async -> PlatformImage? {
        for source in requests {
            guard !Task.isCancelled else { return nil }
            guard let url = source.url else { continue }
            if let image = try? await image(for: url) {
                guard !Task.isCancelled else { return nil }
                return image
            }
        }
        return nil
    }

    func removeItem(for url: URL) {
        let request = ImageRequest(url: url)
        cache.removeCachedImage(for: request)
        cache.removeCachedData(for: request)
        if let key = ImageCacheKeys.poster(for: url) {
            configuration.dataCache?.removeData(for: key)
        }
    }
}
