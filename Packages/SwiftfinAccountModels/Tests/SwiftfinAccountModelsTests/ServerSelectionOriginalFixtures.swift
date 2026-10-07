//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation
import SwiftfinAccountModels

#if !SWIFT_PACKAGE
private final class ServerSelectionFixtureBundle: NSObject {}
#endif

struct ServerSelectionOriginalFixture: Decodable {
    struct Original: Decodable {
        let commit: String
        let path: String
        let sha256: String
    }

    struct Case: Decodable {
        let label: String
        let raw: String
        let json: String
        let defaults: String
        let selectedIndex: Int
        let roundtripKind: String
        var value: ServerSelection {
            label == "all" ? .all : .server(id: raw)
        }
    }

    let original: Original
    let cases: [Case]
    let equalities: [[Bool]]
    let hashSetCount: Int
    static func load() throws -> Self {
        #if SWIFT_PACKAGE
        guard let url = Bundle.module.url(forResource: "server-selection-original-98e6c8b7", withExtension: "json") else {
            throw CocoaError(.fileNoSuchFile)
        }
        #else
        guard let url = Bundle(for: ServerSelectionFixtureBundle.self).url(
            forResource: "server-selection-original-98e6c8b7",
            withExtension: "json"
        ) else {
            throw CocoaError(.fileNoSuchFile)
        }
        #endif
        return try JSONDecoder().decode(Self.self, from: Data(contentsOf: url))
    }

    static var records: [ServerAccountRecord] {
        let url = URL(string: "http://192.0.2.1")!
        return ["A", "A", "a", "", " A ", "家🧒", "swiftfin-all"].enumerated().map { index, id in
            ServerAccountRecord(urls: [url], currentURL: url, name: "record-\(index)", id: id, userIDs: [])
        }
    }
}
