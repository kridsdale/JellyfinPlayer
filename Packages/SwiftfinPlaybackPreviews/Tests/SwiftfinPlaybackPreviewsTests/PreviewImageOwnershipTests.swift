//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

#if canImport(UIKit)
import Foundation
import SwiftfinPlaybackPreviews
import UIKit
import XCTest

@MainActor
final class PreviewImageOwnershipTests: XCTestCase {
    private final class Provider: PreviewImageProvider {
        var requests: [Int] = []
        var current = true
        var indexLookups = 0
        var cached: [Int: UIImage] = [:]
        private var pending: [Int: CheckedContinuation<UIImage?, Never>] = [:]
        private var starts: [Int: CheckedContinuation<Void, Never>] = [:]
        func imageIndex(for seconds: Duration) -> Int? {
            indexLookups += 1
            return current ? Int(seconds.components.seconds) : nil
        }

        func image(for seconds: Duration) async -> UIImage? {
            let index = imageIndex(for: seconds)!
            requests.append(index)
            if let cached = cached[index] {
                return cached
            }
            return await withCheckedContinuation { continuation in
                pending[index] = continuation
                starts.removeValue(forKey: index)?.resume()
            }
        }

        func started(_ index: Int) async {
            if pending[index] != nil {
                return
            }
            await withCheckedContinuation { starts[index] = $0 }
        }

        func finish(_ index: Int, image: UIImage?) {
            pending.removeValue(forKey: index)?.resume(returning: image)
        }

        func invalidate() {
            for index in Array(pending.keys) {
                finish(index, image: nil)
            }
        }
    }

    private func sprite(scale: CGFloat = 2) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        return UIGraphicsImageRenderer(size: CGSize(width: 4, height: 4), format: format).image { context in
            for (index, color) in [UIColor.red, .green, .blue, .yellow].enumerated() {
                color.setFill()
                context.fill(CGRect(x: index % 2 * 2, y: index / 2 * 2, width: 2, height: 2))
            }
        }
    }

    private func pixel(_ image: UIImage) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: 4)
        bytes.withUnsafeMutableBytes { buffer in
            let context = CGContext(
                data: buffer.baseAddress,
                width: 1,
                height: 1,
                bitsPerComponent: 8,
                bytesPerRow: 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )!
            context.draw(image.cgImage!, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        }
        return bytes
    }

    private func waitUntil(_ predicate: () -> Bool) async {
        for _ in 0 ..< 200 {
            if predicate() {
                return
            }
            try? await Task.sleep(for: .milliseconds(5))
        }
        XCTFail("Preview publication did not complete")
    }

    func testCropUsesPixelsPreservesScaleAndSelectsAllFourTiles() throws {
        let source = sprite()
        for (index, rgb) in [[255, 0, 0], [0, 255, 0], [0, 0, 255], [255, 255, 0]].enumerated() {
            let tile = try XCTUnwrap(PreviewTileCrop.image(source, columns: 2, rows: 2, index: index))
            XCTAssertEqual(tile.cgImage?.width, 4)
            XCTAssertEqual(tile.cgImage?.height, 4)
            XCTAssertEqual(tile.scale, 2)
            XCTAssertEqual(tile.imageOrientation, source.imageOrientation)
            XCTAssertEqual(Array(pixel(tile).prefix(3)).map(Int.init), rgb)
        }
    }

    func testCropRejectsInvalidDimensionsIndexesAndOverflow() {
        let source = sprite()
        for (columns, rows, index) in [(0, 2, 0), (2, 0, 0), (-1, 2, 0), (2, 2, -1), (2, 2, 4), (Int.max, 2, 0), (100, 2, 0)] {
            XCTAssertNil(PreviewTileCrop.image(source, columns: columns, rows: rows, index: index))
        }
    }

    func testFinalChapterLoadsOnceAndInvalidationDiscardsCachedImages() async throws {
        let bytes = try XCTUnwrap(sprite().pngData())
        let first = try XCTUnwrap(URL(string: "https://localhost.invalid/first")),
            last = try XCTUnwrap(URL(string: "https://localhost.invalid/last"))
        var requests: [URL] = []
        let provider = ChapterPreviewImageProvider(
            chapters: [.init(start: .zero, url: first), .init(start: .seconds(10), url: last)],
            isCurrent: { true }
        ) { url in
            requests.append(url)
            return bytes
        }
        let image = await provider.image(for: .seconds(100)), again = await provider.image(for: .seconds(11))
        XCTAssertNotNil(image)
        XCTAssertTrue(image === again)
        XCTAssertEqual(requests, [last])
        XCTAssertEqual(provider.imageIndex(for: .seconds(10)), 1)
        provider.invalidate()
        let stale = await provider.image(for: .seconds(11))
        XCTAssertNil(stale)
        XCTAssertNil(provider.imageIndex(for: .zero))
        XCTAssertEqual(requests, [last])
    }

    func testInvalidImageBytesDoNotPoisonRetry() async throws {
        var requests = 0
        let bytes = try XCTUnwrap(sprite().pngData())
        let provider = ChapterPreviewImageProvider(
            chapters: [.init(start: .zero, url: URL(string: "https://localhost.invalid/image"))],
            isCurrent: { true }
        ) { _ in
            requests += 1
            return requests == 1 ? Data([0, 1, 2]) : bytes
        }
        let first = await provider.image(for: .zero), retry = await provider.image(for: .zero)
        XCTAssertNil(first)
        XCTAssertNotNil(retry)
        XCTAssertEqual(requests, 2)
    }

    func testSpriteSheetBoundaryAndBoundedAdjacentWarmup() async throws {
        let layout = try XCTUnwrap(TrickplayPreviewLayout(
            columns: 2,
            rows: 2,
            width: 320,
            intervalMilliseconds: 1000,
            runtime: .seconds(8)
        ))
        let bytes = try XCTUnwrap(sprite(scale: 1).pngData())
        var requests: [Int] = []
        let provider = TrickplayPreviewImageProvider(layout: layout, isCurrent: { true }) { index in
            requests.append(index)
            return bytes
        }
        let firstResult = await provider.image(for: .seconds(4)), nextResult = await provider.image(for: .seconds(5))
        let first = try XCTUnwrap(firstResult), next = try XCTUnwrap(nextResult)
        await waitUntil { requests.contains(0) }
        XCTAssertEqual(Array(pixel(first).prefix(3)), [255, 0, 0])
        XCTAssertEqual(Array(pixel(next).prefix(3)), [0, 255, 0])
        XCTAssertEqual(requests.sorted(), [0, 1])
        XCTAssertEqual(provider.imageIndex(for: .seconds(8)), 7)
        provider.invalidate()
    }

    func testInvalidationAfterDecodeBeforePublicationRejectsPixels() async {
        let provider = Provider(), selection = PreviewImageSelection(provider: provider)
        selection.request(.zero)
        await provider.started(0)
        provider.current = false
        provider.finish(0, image: sprite())
        await waitUntil { provider.indexLookups >= 2 }
        XCTAssertNil(selection.image)
        XCTAssertNil(selection.index)
        selection.stop()
    }

    func testSelectionOnlyPublishesLatestRequestDespiteNoncooperatingOldLoad() async {
        let provider = Provider(), selection = PreviewImageSelection(provider: provider)
        selection.request(.zero)
        await provider.started(0)
        selection.request(.seconds(1))
        await provider.started(1)
        let latest = sprite()
        provider.finish(1, image: latest)
        await waitUntil { selection.index == 1 }
        provider.finish(0, image: sprite())
        for _ in 0 ..< 10 {
            await Task.yield()
        }
        XCTAssertTrue(selection.image === latest)
        XCTAssertEqual(selection.index, 1)
        selection.stop()
    }

    func testReturningToAlreadyDisplayedTileCancelsPendingDifferentTile() async {
        let provider = Provider(), selection = PreviewImageSelection(provider: provider)
        let first = sprite()
        provider.cached[0] = first
        selection.request(.zero)
        await waitUntil { selection.index == 0 }
        selection.request(.seconds(1))
        await provider.started(1)
        selection.request(.zero)
        provider.finish(1, image: sprite())
        for _ in 0 ..< 10 {
            await Task.yield()
        }
        XCTAssertEqual(selection.index, 0)
        XCTAssertTrue(selection.image === first)
        XCTAssertEqual(provider.requests, [0, 1])
        selection.stop()
    }

    func testStoppingSelectionRejectsLateImageAndOwnerCanRelease() async {
        let provider = Provider()
        var selection: PreviewImageSelection? = PreviewImageSelection(provider: provider)
        weak let weakSelection = selection
        selection?.request(.zero)
        await provider.started(0)
        selection?.stop()
        provider.finish(0, image: sprite())
        for _ in 0 ..< 10 {
            await Task.yield()
        }
        XCTAssertNil(selection?.image)
        selection?.request(.seconds(1))
        await provider.started(1)
        selection = nil
        XCTAssertNil(weakSelection)
        provider.finish(1, image: sprite())
    }
}
#endif
