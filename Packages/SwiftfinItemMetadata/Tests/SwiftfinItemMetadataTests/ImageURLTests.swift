//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation
import Get
import SwiftfinItemMetadata
import SwiftfinNetworking
import Testing

@MainActor
private final class URLPort: JellyfinURLResolving {
    var paths: [String] = []
    var flags: [Bool] = []
    var query: [String: String] = [:]
    var result = URL(string: "https://fixture.example/image")
    func url(with request: Request<some Any>, queryAPIKey: Bool) -> URL? {
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
