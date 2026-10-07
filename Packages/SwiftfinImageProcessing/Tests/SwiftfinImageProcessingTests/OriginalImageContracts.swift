//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import CoreGraphics
import Foundation
import SwiftfinImageProcessing
import Testing

struct OriginalImageContracts {
    private struct ImageCase: Decodable {
        let name: String
        let width: Int
        let height: Int
        let bytes: Data
        let expected: [CGFloat]?
    }

    private struct EncodingCase: Decodable {
        let name: String
        let alpha: UInt32
        let png: Data?
        let jpeg: Data?
        let limit: Int?
        let data: Data?
        let contentType: String?
        let error: String?
    }

    private struct Capture: Decodable {
        let originalCommit: String
        let sourceHashes: [String: String]
        let images: [ImageCase]
        let encodings: [EncodingCase]
    }

    @Test
    func `independently executed original pixels and encoding outputs match`() throws {
        let url = try #require(Bundle.module.url(forResource: "image-original-c5b3e16b", withExtension: "json"))
        let capture = try JSONDecoder().decode(Capture.self, from: Data(contentsOf: url))
        #expect(capture.originalCommit == "c5b3e16b40a888ded490a08b3c3b4b84c394c3e7")
        #expect(capture.sourceHashes == [
            "Shared/Extensions/UIImage+InterestingColor.swift": "d9a2b3f1e8dc1fe376afb65eadbef5a0e65f5f1fa6490298c79a459dcc6feb74",
            "Shared/Extensions/UIImage.swift": "7ea196741ac25cbdfcd77f670ba35eedb1590f5c905547740b36f51019283167"
        ])
        #expect(capture.images.count == 9 && capture.encodings.count == 28)
        for fixture in capture.images {
            let image = try #require(SyntheticImage(name: fixture.name, width: fixture.width, height: fixture.height, bytes: fixture.bytes)
                .image())
            let actual = ImagePalette.interestingColor(in: image)
            if let expected = fixture.expected {
                let color = try #require(actual)
                #expect(
                    zip([color.red, color.green, color.blue], expected).allSatisfy { abs($0 - $1) < 0.000_001 },
                    Comment(rawValue: fixture.name)
                )
            } else {
                #expect(actual == nil, Comment(rawValue: fixture.name))
            }
        }
        for fixture in capture.encodings {
            let alpha = try #require(CGImageAlphaInfo(rawValue: fixture.alpha))
            do {
                let value = try ImageDataEncoding.encode(
                    hasAlpha: ImageDataEncoding.hasAlpha(alpha),
                    maximumByteCount: fixture.limit,
                    png: { fixture.png },
                    jpeg: { fixture.jpeg }
                )
                #expect(
                    fixture.error == nil && value.data == fixture.data && value.contentType == fixture.contentType,
                    Comment(rawValue: fixture.name)
                )
            } catch let error as ImageEncodingError {
                let originalError = try #require(fixture.error)
                if originalError == "Unknown error" {
                    #expect(error == .encodingFailed)
                } else {
                    #expect(originalError.hasPrefix("Image is too large ("))
                    guard case let .exceedsLimit(actual, maximum) = error else { Issue.record("Wrong error kind")
                        continue
                    }
                    #expect(maximum == fixture.limit && actual > maximum)
                }
            }
        }
    }
}
