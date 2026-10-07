//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import CoreGraphics
import Foundation

public struct EncodedImageData: Sendable, Equatable {
    public let data: Data
    public let contentType: String
}

public enum ImageEncodingError: Error, Sendable, Equatable {
    case exceedsLimit(actual: Int, maximum: Int)
    case encodingFailed
}

/// Selects encoding and validates bytes without platform UI or localization policy.
public enum ImageDataEncoding {
    public static func hasAlpha(_ alpha: CGImageAlphaInfo?) -> Bool {
        guard let alpha else { return false }
        return [.alphaOnly, .first, .last, .premultipliedFirst, .premultipliedLast].contains(alpha)
    }

    public static func encode(
        hasAlpha: Bool,
        maximumByteCount: Int? = 30_000_000,
        png: () -> Data?,
        jpeg: () -> Data?
    ) throws -> EncodedImageData {
        let result: EncodedImageData
        if hasAlpha, let data = png() {
            result = .init(data: data, contentType: "image/png")
        } else if let data = jpeg() {
            result = .init(data: data, contentType: "image/jpeg")
        } else {
            throw ImageEncodingError.encodingFailed
        }
        if let maximumByteCount, result.data.count > maximumByteCount {
            throw ImageEncodingError.exceedsLimit(actual: result.data.count, maximum: maximumByteCount)
        }
        return result
    }
}
