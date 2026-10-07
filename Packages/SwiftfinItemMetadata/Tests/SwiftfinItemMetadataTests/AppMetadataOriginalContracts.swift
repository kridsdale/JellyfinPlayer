//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation
import JellyfinAPI
import SwiftfinItemMetadata
import Testing

struct AppMetadataOriginalContracts {
    private struct Fixture: Decodable {
        struct Blur: Decodable { let variant: String
            let type: String
            let entries: [String: String]?
        }

        struct Refresh: Decodable { let `case`: String
            let replaceMetadata: Bool
            let mode: String
            let falseSelection: Bool
            let trueSelection: Bool
        }

        let blurHashes: [Blur]
        let refresh: [Refresh]
    }

    private let original = #"""
    {
      "blurHashes": [
        {
          "entries": {
            "tag": "primary"
          },
          "type": "Primary",
          "variant": "full"
        },
        {
          "entries": {
            "tag": "art"
          },
          "type": "Art",
          "variant": "full"
        },
        {
          "entries": {
            "tag": "backdrop"
          },
          "type": "Backdrop",
          "variant": "full"
        },
        {
          "entries": {
            "tag": "banner"
          },
          "type": "Banner",
          "variant": "full"
        },
        {
          "entries": {
            "tag": "logo"
          },
          "type": "Logo",
          "variant": "full"
        },
        {
          "entries": {
            "tag": "thumb"
          },
          "type": "Thumb",
          "variant": "full"
        },
        {
          "entries": {
            "tag": "disc"
          },
          "type": "Disc",
          "variant": "full"
        },
        {
          "entries": {
            "tag": "box"
          },
          "type": "Box",
          "variant": "full"
        },
        {
          "entries": {
            "tag": "screenshot"
          },
          "type": "Screenshot",
          "variant": "full"
        },
        {
          "entries": {
            "tag": "menu"
          },
          "type": "Menu",
          "variant": "full"
        },
        {
          "entries": {
            "tag": "chapter"
          },
          "type": "Chapter",
          "variant": "full"
        },
        {
          "entries": {
            "tag": "boxRear"
          },
          "type": "BoxRear",
          "variant": "full"
        },
        {
          "entries": {
            "tag": "profile"
          },
          "type": "Profile",
          "variant": "full"
        },
        {
          "entries": null,
          "type": "Primary",
          "variant": "missing"
        },
        {
          "entries": null,
          "type": "Art",
          "variant": "missing"
        },
        {
          "entries": null,
          "type": "Backdrop",
          "variant": "missing"
        },
        {
          "entries": null,
          "type": "Banner",
          "variant": "missing"
        },
        {
          "entries": null,
          "type": "Logo",
          "variant": "missing"
        },
        {
          "entries": null,
          "type": "Thumb",
          "variant": "missing"
        },
        {
          "entries": null,
          "type": "Disc",
          "variant": "missing"
        },
        {
          "entries": null,
          "type": "Box",
          "variant": "missing"
        },
        {
          "entries": null,
          "type": "Screenshot",
          "variant": "missing"
        },
        {
          "entries": null,
          "type": "Menu",
          "variant": "missing"
        },
        {
          "entries": null,
          "type": "Chapter",
          "variant": "missing"
        },
        {
          "entries": null,
          "type": "BoxRear",
          "variant": "missing"
        },
        {
          "entries": null,
          "type": "Profile",
          "variant": "missing"
        },
        {
          "entries": {},
          "type": "Primary",
          "variant": "empty"
        },
        {
          "entries": null,
          "type": "Art",
          "variant": "empty"
        },
        {
          "entries": null,
          "type": "Backdrop",
          "variant": "empty"
        },
        {
          "entries": null,
          "type": "Banner",
          "variant": "empty"
        },
        {
          "entries": null,
          "type": "Logo",
          "variant": "empty"
        },
        {
          "entries": null,
          "type": "Thumb",
          "variant": "empty"
        },
        {
          "entries": null,
          "type": "Disc",
          "variant": "empty"
        },
        {
          "entries": null,
          "type": "Box",
          "variant": "empty"
        },
        {
          "entries": null,
          "type": "Screenshot",
          "variant": "empty"
        },
        {
          "entries": null,
          "type": "Menu",
          "variant": "empty"
        },
        {
          "entries": null,
          "type": "Chapter",
          "variant": "empty"
        },
        {
          "entries": null,
          "type": "BoxRear",
          "variant": "empty"
        },
        {
          "entries": null,
          "type": "Profile",
          "variant": "empty"
        }
      ],
      "refresh": [
        {
          "case": "scan",
          "falseSelection": false,
          "mode": "Default",
          "replaceMetadata": false,
          "trueSelection": false
        },
        {
          "case": "missing",
          "falseSelection": false,
          "mode": "FullRefresh",
          "replaceMetadata": false,
          "trueSelection": true
        },
        {
          "case": "all",
          "falseSelection": false,
          "mode": "FullRefresh",
          "replaceMetadata": true,
          "trueSelection": true
        }
      ]
    }
    """#
    private func fixture() throws -> Fixture {
        try JSONDecoder().decode(Fixture.self, from: Data(original.utf8))
    }

    @Test
    func `all original blurhash fields preserve absent empty and full dictionaries`() throws {
        var full = ImageBlurHashes()
        full.primary = ["tag": "primary"]
        full.art = ["tag": "art"]
        full.backdrop = ["tag": "backdrop"]
        full.banner = ["tag": "banner"]
        full.logo = ["tag": "logo"]
        full.thumb = ["tag": "thumb"]
        full.disc = ["tag": "disc"]
        full.box = ["tag": "box"]
        full.screenshot = ["tag": "screenshot"]
        full.menu = ["tag": "menu"]
        full.chapter = ["tag": "chapter"]
        full.boxRear = ["tag": "boxRear"]
        full.profile = ["tag": "profile"]
        var empty = ImageBlurHashes()
        empty.primary = [:]
        for row in try fixture().blurHashes {
            let type = try #require(ImageType(rawValue: row.type))
            let value = row.variant == "full" ? full : row.variant == "empty" ? empty : ImageBlurHashes()
            #expect(value[type] == row.entries)
        }
    }

    @Test
    func `original refresh modes and both replacement selections remain exact`() throws {
        for row in try fixture().refresh {
            let value = try #require(MetadataRefreshSelection.allCases.first { String(describing: $0) == row.case })
            #expect(value.replaceMetadata == row.replaceMetadata)
            #expect(value.metadataRefreshMode.rawValue == row.mode)
            #expect(value.replaceElements(false) == row.falseSelection)
            #expect(value.replaceElements(true) == row.trueSelection)
        }
    }

    @Test
    func `refresh selection is Hashable and transfers without native state`() async {
        let values = MetadataRefreshSelection.allCases
        let returned = await Task.detached { values.map { $0.replaceElements(true) } }.value
        #expect(returned == [false, true, true] && Set(values).count == 3)
    }
}
