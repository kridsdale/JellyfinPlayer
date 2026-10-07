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
#if canImport(UIKit)
import UIKit
#endif

struct ImageProcessingContracts {
    @Test
    func `alpha classification includes exactly original flags`() {
        let included: Set<CGImageAlphaInfo> = [.alphaOnly, .first, .last, .premultipliedFirst, .premultipliedLast]
        for alpha in [
            CGImageAlphaInfo.none,
            .noneSkipFirst,
            .noneSkipLast,
            .alphaOnly,
            .first,
            .last,
            .premultipliedFirst,
            .premultipliedLast
        ] {
            #expect(ImageDataEncoding.hasAlpha(alpha) == included.contains(alpha))
        }
        #expect(!ImageDataEncoding.hasAlpha(nil))
    }

    @Test
    func `alpha prefers PNG and never invokes JPEG`() throws {
        var calls: [String] = []
        let expected = Data([1, 2, 3])
        let value = try ImageDataEncoding.encode(hasAlpha: true, png: { calls.append("png")
            return expected
        }, jpeg: { calls.append("jpeg")
            return Data([4])
        })
        #expect(value.data == expected && value.contentType == "image/png" && calls == ["png"])
    }

    @Test
    func `opaque input skips PNG`() throws {
        var calls: [String] = []
        let expected = Data([4, 5])
        let value = try ImageDataEncoding.encode(hasAlpha: false, png: { calls.append("png")
            return Data([1])
        }, jpeg: { calls.append("jpeg")
            return expected
        })
        #expect(value.data == expected && value.contentType == "image/jpeg" && calls == ["jpeg"])
    }

    @Test
    func `missing PNG has original ordered JPEG fallback`() throws {
        var calls: [String] = []
        let value = try ImageDataEncoding.encode(hasAlpha: true, png: { calls.append("png")
            return nil
        }, jpeg: { calls.append("jpeg")
            return Data([4])
        })
        #expect(value.contentType == "image/jpeg" && calls == ["png", "jpeg"])
    }

    @Test
    func `oversized PNG is rejected without trying smaller JPEG`() {
        var triedJPEG = false
        #expect(throws: ImageEncodingError.exceedsLimit(actual: 3, maximum: 2)) {
            try ImageDataEncoding.encode(hasAlpha: true, maximumByteCount: 2, png: { Data([1, 2, 3]) }, jpeg: { triedJPEG = true
                return Data([4])
            })
        }
        #expect(!triedJPEG)
    }

    @Test
    func `missing both encoders reports failure`() {
        #expect(throws: ImageEncodingError.encodingFailed) {
            try ImageDataEncoding.encode(hasAlpha: true, png: { nil }, jpeg: { nil })
        }
    }

    @Test
    func `exact unbounded zero and negative limits retain original rules`() throws {
        let bytes = Data([1, 2, 3])
        #expect(try ImageDataEncoding.encode(hasAlpha: false, maximumByteCount: 3, png: { nil }, jpeg: { bytes }).data == bytes)
        #expect(try ImageDataEncoding.encode(hasAlpha: false, maximumByteCount: nil, png: { nil }, jpeg: { bytes }).data == bytes)
        #expect(try ImageDataEncoding.encode(hasAlpha: true, maximumByteCount: 0, png: { Data() }, jpeg: { nil }).data.isEmpty)
        #expect(throws: ImageEncodingError.exceedsLimit(actual: 0, maximum: -1)) {
            try ImageDataEncoding.encode(hasAlpha: true, maximumByteCount: -1, png: { Data() }, jpeg: { nil })
        }
    }

    @Test
    func `solid pixels retain exact normalized color`() throws {
        let image = try #require(syntheticImages()[0].image())
        let value = try #require(ImagePalette.interestingColor(in: image))
        #expect(value.red == 1 && value.green == 0 && value.blue == 0)
    }

    @Test
    func `transparency threshold retains premultiplied sampling`() throws {
        let cases = syntheticImages()
        for fixture in cases where fixture.name.contains("ignored") || fixture.name.contains("excluded") {
            #expect(try ImagePalette.interestingColor(in: #require(fixture.image())) == nil)
        }
        let image = try #require(cases.first(where: { $0.name.contains("alpha 128") })?.image())
        let value = try #require(ImagePalette.interestingColor(in: image))
        #expect(abs(value.red - CGFloat(64) / 255) < 0.000_001)
        #expect(abs(value.green - CGFloat(20) / 255) < 0.000_001)
        #expect(abs(value.blue - CGFloat(10) / 255) < 0.000_001)
    }

    @Test
    func `narrow portrait landscape and single pixel sampling stay finite`() throws {
        for fixture in syntheticImages() where fixture.width == 1 || fixture.height == 1 {
            let image = try #require(fixture.image())
            let value = try #require(ImagePalette.interestingColor(in: image))
            #expect([value.red, value.green, value.blue].allSatisfy { $0.isFinite && $0 >= 0 && $0 <= 1 })
        }
    }

    @Test
    func `processing and encoding can run on independent executor`() async throws {
        let fixture = syntheticImages()[0]
        let result = try await Task.detached {
            let color = try ImagePalette.interestingColor(in: #require(fixture.image()))
            let encoded = try ImageDataEncoding.encode(hasAlpha: true, png: { fixture.bytes }, jpeg: { nil })
            return (color, encoded)
        }.value
        #expect(result.0?.red == 1 && result.1.data == fixture.bytes)
    }

    #if canImport(UIKit)
    @MainActor @Test
    func `UI kit encoding retains native PNG bytes`() throws {
        let image = try UIImage(cgImage: #require(syntheticImages()[0].image()))
        let expected = try #require(image.pngData())
        let value = try image.encodedImageData(maximumByteCount: nil)
        #expect(value.data == expected && value.contentType == "image/png")
    }

    @MainActor @Test
    func `UI kit encoding retains native JPEG bytes`() throws {
        let image = try UIImage(cgImage: #require(syntheticImages()[0].image(alpha: .noneSkipLast)))
        let expected = try #require(image.jpegData(compressionQuality: 1))
        let value = try image.encodedImageData(maximumByteCount: nil)
        #expect(value.data == expected && value.contentType == "image/jpeg")
    }
    #endif
}
