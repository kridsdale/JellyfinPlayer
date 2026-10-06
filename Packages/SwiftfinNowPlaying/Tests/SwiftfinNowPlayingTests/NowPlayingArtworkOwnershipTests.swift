//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

// SPDX-License-Identifier: MPL-2.0
#if canImport(UIKit)
import MediaPlayer
@testable import SwiftfinNowPlaying
import UIKit
import XCTest

@MainActor
final class NowPlayingArtworkOwnershipTests: XCTestCase {
    func testMediaPlayerCanRequestImmutableArtworkOffTheUIActor() async throws {
        let size = CGSize(width: 4, height: 4)
        let image = UIGraphicsImageRenderer(size: size).image { context in
            UIColor.red.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
        let requested = await Task.detached {
            let artwork = NowPlayingArtwork.make(image)
            return artwork.image(at: size)
        }.value
        let returned = try XCTUnwrap(requested)
        XCTAssertEqual(returned.size, size)
        XCTAssertEqual(returned.pngData(), image.pngData())
    }
}
#endif
