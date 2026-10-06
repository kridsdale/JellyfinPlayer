//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

// SPDX-License-Identifier: MPL-2.0
import Foundation
import KidsArtwork
@testable import KidsArtworkUI
import KidsDomain
import UIKit
import XCTest

final class KidsArtworkBoundaryTests: XCTestCase {
    private let binding = KidsBinding(serverID: "test-server", userID: "test-child", showsID: "tv", moviesID: "movies")
    private var item: KidsItem {
        .init(id: "show", name: "Fixture", kind: .series, libraryID: "tv", imageTag: "tag", imageOwnerID: "show")
    }

    private actor ImageSource {
        let data: Data
        var requests = 0
        init(_ data: Data) {
            self.data = data
        }

        func read() async throws -> Data {
            requests += 1
            try await Task.sleep(for: .milliseconds(20))
            return data
        }
    }

    @MainActor
    private func fixture() -> (KidsArtworkStore, ImageSource) {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 24, height: 24)).image { context in
            UIColor.magenta.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 24, height: 24))
        }
        let source = ImageSource(image.pngData()!)
        let cache = KidsArtworkCache(binding: binding) { _, _ in try await source.read() }
        return (KidsArtworkStore(cache: cache, binding: binding), source)
    }

    @MainActor
    func testDeniedImageScopeNeverFetchesBytes() async {
        let (store, source) = fixture()
        var anotherLibrary = item
        anotherLibrary.libraryID = "unapproved"
        var forgedOwner = item
        forgedOwner.imageOwnerID = "another-show"
        for candidate in [anotherLibrary, forgedOwner] {
            do { _ = try await store.image(for: candidate, binding: binding)
                XCTFail("Denied item returned artwork")
            } catch { XCTAssertEqual(error as? KidsContractError, .denied) }
        }
        var changed = binding
        changed.userID = "another-child"
        do { _ = try await store.image(for: item, binding: changed)
            XCTFail("Changed account returned artwork")
        } catch { XCTAssertEqual(error as? KidsContractError, .denied) }
        let requests = await source.requests
        XCTAssertEqual(requests, 0)
    }

    @MainActor
    func testConcurrentLoadsAndRevisitSharePreparedPixels() async throws {
        let (store, source) = fixture()
        let item = item, binding = binding
        let first = Task { @MainActor in try await store.image(for: item, binding: binding) }
        let second = Task { @MainActor in try await store.image(for: item, binding: binding) }
        let a = try await first.value
        let b = try await second.value
        let revisited = try await store.image(for: item, binding: binding)
        XCTAssertTrue(a === b)
        XCTAssertTrue(a === revisited)
        XCTAssertNotNil(a.cgImage)
        let requests = await source.requests
        XCTAssertEqual(requests, 1)
    }

    @MainActor
    func testInvalidationCannotReturnPriorAccountPixels() async throws {
        let (store, source) = fixture()
        _ = try await store.image(for: item, binding: binding)
        store.invalidate()
        do { _ = try await store.image(for: item, binding: binding)
            XCTFail("Invalidated store returned prior pixels")
        } catch { XCTAssertEqual(error as? KidsContractError, .denied) }
        let requests = await source.requests
        XCTAssertEqual(requests, 1)
    }
}
