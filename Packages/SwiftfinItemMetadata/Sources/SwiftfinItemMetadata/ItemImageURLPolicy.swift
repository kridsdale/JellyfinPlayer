//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation
import JellyfinAPI
import SwiftfinNetworking

@MainActor
public enum ItemImageURLPolicy {
    public static func url(
        using urls: any JellyfinURLResolving,
        itemID: String,
        type: String,
        index: Int? = nil,
        tag: String? = nil,
        maxWidth: Int? = nil,
        maxHeight: Int? = nil,
        quality: Int? = nil,
        png: Bool = false
    ) -> URL? {
        let parameters = Paths.GetItemImageParameters(
            maxWidth: maxWidth,
            maxHeight: maxHeight,
            quality: quality,
            tag: tag,
            format: png ? .png : nil,
            imageIndex: index
        )
        return urls.url(with: Paths.getItemImage(itemID: itemID, imageType: type, parameters: parameters), queryAPIKey: false)
    }
}
