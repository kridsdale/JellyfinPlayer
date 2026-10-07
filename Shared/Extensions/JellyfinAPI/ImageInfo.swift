//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation
import JellyfinAPI
import SwiftfinImages
import SwiftfinItemMetadata
import SwiftfinNetworking

extension ImageInfo: @retroactive Identifiable {

    public var id: Int {
        hashValue
    }

    @MainActor
    func itemImageSource(itemID: String, client: JellyfinTransport) -> ImageSource {
        let itemImageURL = ItemImageURLPolicy.url(
            using: client,
            itemID: itemID,
            type: imageType?.rawValue ?? "",
            index: imageIndex,
            tag: imageTag
        )

        return ImageSource(url: itemImageURL)
    }
}
