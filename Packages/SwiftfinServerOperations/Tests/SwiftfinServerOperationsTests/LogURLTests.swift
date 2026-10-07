//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation
import Get
import SwiftfinNetworking
import SwiftfinServerOperations
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
func `diagnostic download URL preserves exact name and query authentication`() {
    let urls = URLPort()
    _ = ServerDiagnosticURLPolicy.logURL(name: "fixture.log", using: urls)
    #expect(urls.paths == ["/System/Logs/Log"])
    #expect(urls.query == ["name": "fixture.log"])
    #expect(urls.flags == [true])
}

@Test @MainActor
func `diagnostic download does not invent URL when resolver cannot resolve`() {
    let urls = URLPort()
    urls.result = nil
    #expect(ServerDiagnosticURLPolicy.logURL(name: "fixture.log", using: urls) == nil)
}
