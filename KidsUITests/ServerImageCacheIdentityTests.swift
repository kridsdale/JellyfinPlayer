//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation
import XCTest

@MainActor
final class ServerImageCacheIdentityTests: XCTestCase {
    func testNativeCallbackReadsValuesOnBackgroundExecutor() async throws {
        let index = ServerImageCacheIdentityIndex()
        let first = try XCTUnwrap(URL(string: "http://192.0.2.1:8096"))
        let alternate = try XCTUnwrap(URL(string: "http://example.invalid:8096"))
        index.replace([first: "server-A", alternate: "server-A"])
        let values = await Task.detached {
            [index.serverID(for: first), index.serverID(for: alternate)]
        }.value
        XCTAssertEqual(values, ["server-A", "server-A"])
    }

    func testReplacementInvalidatesRemovedServersAndRebindsSameURL() async throws {
        let index = ServerImageCacheIdentityIndex()
        let first = try XCTUnwrap(URL(string: "http://192.0.2.1:8096"))
        let removed = try XCTUnwrap(URL(string: "http://192.0.2.2:8096"))
        index.replace([first: "server-A", removed: "server-B"])
        index.replace([first: "server-C"])
        let values = await Task.detached {
            [index.serverID(for: first), index.serverID(for: removed)]
        }.value
        XCTAssertEqual(values, ["server-C", nil])
    }
}
