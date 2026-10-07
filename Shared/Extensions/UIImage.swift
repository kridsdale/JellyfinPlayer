//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import SwiftfinImageProcessing
import SwiftfinLocalization
import UIKit

extension UIImage {
    @MainActor
    func data(maxSize: Int? = 30_000_000) throws -> (data: Data, contentType: String) {
        do {
            let encoded = try encodedImageData(maximumByteCount: maxSize)
            return (encoded.data, encoded.contentType)
        } catch let ImageEncodingError.exceedsLimit(actual, maximum) {
            throw ErrorMessage(
                "Image is too large (\(actual.formatted(.byteCount(style: .file))) / \(maximum.formatted(.byteCount(style: .file)))"
            )
        } catch {
            throw ErrorMessage(L10n.unknownError)
        }
    }
}
