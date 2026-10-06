//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import CoreSpotlight
import Foundation

struct SwiftfinSpotlight {

    func addSwiftfinToSpotlight() {
        Task.detached {
            // The index and its mutable items belong only to this task.
            let mainIndex = CSSearchableIndex(name: "KidsJellyFinAppIndex")
            let attributeSet = CSSearchableItemAttributeSet(contentType: UTType.application)
            attributeSet.title = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? "KidsJellyFin"

            let searchableItem = CSSearchableItem(
                uniqueIdentifier: Bundle.main.bundleIdentifier ?? "com.kridsdale.JellyfinPlayer",
                domainIdentifier: nil,
                attributeSet: attributeSet
            )

            try? await mainIndex.indexSearchableItems([searchableItem])
        }
    }
}
