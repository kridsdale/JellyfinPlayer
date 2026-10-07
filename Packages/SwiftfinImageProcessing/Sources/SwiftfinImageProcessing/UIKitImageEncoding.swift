//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

#if canImport(UIKit)
import UIKit

@MainActor
public extension UIImage {
    func encodedImageData(maximumByteCount: Int? = 30_000_000) throws -> EncodedImageData {
        try ImageDataEncoding.encode(
            hasAlpha: ImageDataEncoding.hasAlpha(cgImage?.alphaInfo),
            maximumByteCount: maximumByteCount,
            png: { pngData() },
            jpeg: { jpegData(compressionQuality: 1) }
        )
    }
}
#endif
