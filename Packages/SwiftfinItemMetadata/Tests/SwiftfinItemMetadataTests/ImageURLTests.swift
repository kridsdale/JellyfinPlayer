//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation
import Get
import JellyfinAPI
import SwiftfinItemMetadata
import SwiftfinNetworking
import Testing

@MainActor
private final class URLPort: JellyfinURLResolving, JellyfinRequestSending {
    var current = true
    var onResolve: @MainActor () -> Void = {}
    var requestCount = 0
    func value<Value: Decodable & Sendable>(for request: Request<Value>) async throws -> Value {
        requestCount += 1
        throw CancellationError()
    }

    func complete(_ request: Request<Void>) async throws {
        requestCount += 1
        throw CancellationError()
    }

    var paths: [String] = []
    var flags: [Bool] = []
    var query: [String: String] = [:]
    var result = URL(string: "https://fixture.example/image")
    func url(with request: Request<some Any>, queryAPIKey: Bool) -> URL? {
        onResolve()
        paths.append(request.url?.path ?? "")
        flags.append(queryAPIKey)
        query = Dictionary(uniqueKeysWithValues: (request.query ?? []).compactMap { k, v in v.map { (k, $0) } })
        return result
    }

    func url(path: String) -> URL? {
        result
    }
}

@Test @MainActor
func `image URL preserves scaled dimensions quality tag index and logo format`() {
    let urls = URLPort()
    _ = ItemImageURLPolicy.url(
        using: urls,
        itemID: "item",
        type: "Logo",
        index: 2,
        tag: "tag",
        maxWidth: 800,
        maxHeight: 400,
        quality: 90,
        png: true
    )
    #expect(urls.paths == ["/Items/item/Images/Logo"])
    #expect(urls.query == ["maxWidth": "800", "maxHeight": "400", "quality": "90", "tag": "tag", "imageIndex": "2", "format": "Png"])
    #expect(urls.flags == [false])
}

@Test @MainActor
func `image URL nil resolver and optional fields remain nil`() {
    let urls = URLPort()
    urls.result = nil
    #expect(ItemImageURLPolicy.url(using: urls, itemID: "item", type: "Chapter") == nil)
    #expect(urls.query.isEmpty)
    #expect(urls.flags == [false])
}

@MainActor
private func boundImageClient(_ urls: URLPort, includesURLs: Bool = true) -> ItemMetadataClient {
    .init(
        executor: .init(sender: urls, isCurrent: { urls.current }),
        userID: "original-user",
        bindingID: .init(transport: ObjectIdentifier(urls), userID: "original-user"),
        urls: includesURLs ? urls : nil
    )
}

@Test @MainActor
func `editor image URL uses original item resolver index tag without any request`() throws {
    let urls = URLPort()
    let editor = try boundImageClient(urls).makeEditor(itemID: "original-item")
    let image = ImageInfo(imageIndex: 3, imageTag: "original-tag", imageType: .backdrop)
    let result = try editor.imageURL(image)
    #expect(result == urls.result)
    #expect(urls.paths == ["/Items/original-item/Images/Backdrop"])
    #expect(urls.query == ["imageIndex": "3", "tag": "original-tag"])
    #expect(urls.flags == [false] && urls.requestCount == 0)
}

@Test @MainActor
func `retired editor binding rejects URL before invoking resolver`() throws {
    let urls = URLPort(), editor = try boundImageClient(urls).makeEditor(itemID: "item")
    urls.current = false
    #expect(throws: CancellationError.self) { try editor.imageURL(.init(imageType: .primary)) }
    #expect(urls.paths.isEmpty && urls.requestCount == 0)
}

@Test @MainActor
func `resolver account reentry rejects obsolete URL after resolution`() throws {
    let urls = URLPort(), editor = try boundImageClient(urls).makeEditor(itemID: "item")
    urls.onResolve = { urls.current = false }
    #expect(throws: CancellationError.self) { try editor.imageURL(.init(imageType: .primary)) }
    #expect(urls.paths.count == 1 && urls.requestCount == 0)
}

@Test @MainActor
func `missing resolver and retired caller neither infer another account nor perform reads`() throws {
    let urls = URLPort(), editor = try boundImageClient(urls, includesURLs: false).makeEditor(itemID: "item")
    #expect(try editor.imageURL(.init(imageType: .primary)) == nil)
    #expect(throws: CancellationError.self) { try editor.imageURL(.init(imageType: .primary), validate: { throw CancellationError() }) }
    #expect(urls.paths.isEmpty && urls.requestCount == 0)
}
