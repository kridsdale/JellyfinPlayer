//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

#if canImport(UIKit)
import Combine
import Foundation
import UIKit

@MainActor
public protocol PreviewImageProvider: ObservableObject {
    func image(for seconds: Duration) async -> UIImage?
    func imageIndex(for seconds: Duration) -> Int?
    func invalidate()
}

@MainActor
public final class ChapterPreviewImageProvider: PreviewImageProvider {
    private let chapters: [PreviewChapter]
    private let cache: PreviewImageCache<UIImage>
    public init(
        chapters: [PreviewChapter],
        isCurrent: @escaping @MainActor @Sendable () -> Bool,
        load: @escaping @MainActor @Sendable (URL) async -> Data?
    ) {
        self.chapters = chapters
        cache = PreviewImageCache(isCurrent: isCurrent) { index in
            guard chapters.indices.contains(index), let url = chapters[index].url,
                  let bytes = await load(url), !Task.isCancelled else { return nil }
            return UIImage(data: bytes)
        }
    }

    public func imageIndex(for seconds: Duration) -> Int? {
        guard cache.isValid else { return nil }
        return ChapterPreviewTimeline.index(for: seconds, chapters: chapters)
    }

    public func image(for seconds: Duration) async -> UIImage? {
        guard let index = imageIndex(for: seconds) else { return nil }
        return await cache.image(at: index)
    }

    public func invalidate() {
        cache.invalidate()
    }
}

@MainActor
public final class TrickplayPreviewImageProvider: PreviewImageProvider {
    private let layout: TrickplayPreviewLayout
    private let cache: PreviewImageCache<UIImage>
    public init(
        layout: TrickplayPreviewLayout,
        isCurrent: @escaping @MainActor @Sendable () -> Bool,
        load: @escaping @MainActor @Sendable (Int) async -> Data?
    ) {
        self.layout = layout
        cache = PreviewImageCache(isCurrent: isCurrent) { index in
            guard let bytes = await load(index), !Task.isCancelled else { return nil }
            return UIImage(data: bytes)
        }
    }

    public func imageIndex(for seconds: Duration) -> Int? {
        guard cache.isValid else { return nil }
        return layout.address(for: seconds)?.interval
    }

    public func image(for seconds: Duration) async -> UIImage? {
        guard cache.isValid, let address = layout.address(for: seconds),
              let sheet = await cache.image(at: address.sheet), !Task.isCancelled else { return nil }
        cache.prefetch(layout.adjacentSheets(to: address))
        return PreviewTileCrop.image(sheet, columns: layout.columns, rows: layout.rows, index: address.tile)
    }

    public func invalidate() {
        cache.invalidate()
    }
}

/// Owns asynchronous scrub-image publication; stale and canceled requests cannot replace the current selection.
@MainActor
public final class PreviewImageSelection: ObservableObject {
    @Published
    public private(set) var image: UIImage?
    @Published
    public private(set) var index: Int?
    private let provider: any PreviewImageProvider
    private var task: Task<Void, Never>?
    private var generation = UUID()

    public init(provider: any PreviewImageProvider) {
        self.provider = provider
    }

    isolated deinit { task?.cancel() }

    public func request(_ seconds: Duration) {
        task?.cancel()
        task = nil
        let request = UUID()
        generation = request
        if image != nil, let next = provider.imageIndex(for: seconds), next == index {
            return
        }
        let provider = self.provider
        task = Task(priority: .userInitiated) { [weak self] in
            let result = await provider.image(for: seconds)
            guard !Task.isCancelled, let self, generation == request else { return }
            if let result, let index = provider.imageIndex(for: seconds) {
                self.image = result
                self.index = index
            } else {
                image = nil
                index = nil
            }
            task = nil
        }
    }

    public func stop() {
        generation = UUID()
        task?.cancel()
        task = nil
        image = nil
        index = nil
    }
}

@MainActor
public enum PreviewTileCrop {
    public static func image(_ image: UIImage, columns: Int, rows: Int, index: Int) -> UIImage? {
        let area = columns.multipliedReportingOverflow(by: rows)
        guard columns > 0, rows > 0, !area.overflow, index >= 0,
              index < area.partialValue, let source = image.cgImage else { return nil }
        let width = source.width / columns, height = source.height / rows
        guard width > 0, height > 0 else { return nil }
        let rect = CGRect(
            x: (index % columns) * width,
            y: (index / columns) * height,
            width: width,
            height: height
        )
        guard let tile = source.cropping(to: rect) else { return nil }
        return UIImage(cgImage: tile, scale: image.scale, orientation: image.imageOrientation)
    }
}
#endif
