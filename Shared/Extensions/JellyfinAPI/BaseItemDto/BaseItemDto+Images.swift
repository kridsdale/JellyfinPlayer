//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import FactoryKit
import Foundation
import JellyfinAPI
import SwiftfinCollections
import SwiftfinImages
import SwiftfinItemMetadata
import SwiftfinValues
import UIKit

extension BaseItemDto {

    @MainActor
    func imageSource(
        _ type: ImageType,
        itemID: String?,
        tag: String? = nil,
        environment: some WithImageSourceOptions
    ) -> ImageSource? {
        let imageTag: String? = switch type {
        case .backdrop:
            backdropImageTags?.first
        case .screenshot:
            screenshotImageTags?.first
        default:
            imageTags?[type.rawValue]
        }

        guard let itemID, itemID.isNotEmpty,
              let tag = tag ?? (itemID == id ? imageTag : nil), tag.isNotEmpty,
              let client = Container.shared.currentUserSession()?.client
        else { return nil }

        // TODO: put into environment?
        let scale = UITraitCollection.current.displayScale

        guard let url = ItemImageURLPolicy.url(
            using: client,
            itemID: itemID,
            type: type.rawValue,
            tag: tag,
            maxWidth: environment.maxWidth.map { Int($0 * scale) },
            maxHeight: environment.maxHeight.map { Int($0 * scale) },
            quality: environment.quality.map { clamp($0, min: 1, max: 100) },
            png: type == .logo
        ) else { return nil }

        let blurHashes = itemID == id && type != .logo ? imageBlurHashes?[type] : nil

        return ImageSource(
            url: url,
            blurHash: blurHashes?[tag] ?? blurHashes?.values.first
        )
    }
}
