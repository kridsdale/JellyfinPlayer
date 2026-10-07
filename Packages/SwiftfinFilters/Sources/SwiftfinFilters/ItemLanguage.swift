//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation
import JellyfinAPI

public struct ItemLanguage: Codable, Hashable, Sendable {

    public let displayTitle: String
    public let value: String

    public init(displayTitle: String, value: String) {
        self.displayTitle = displayTitle
        self.value = value
    }

    public init(from anyFilter: AnyItemFilter) {
        self.displayTitle = anyFilter.displayTitle
        self.value = anyFilter.value
    }

    public init?(_ nameValuePair: NameValuePair) {
        guard let name = nameValuePair.name, let value = nameValuePair.value else { return nil }

        self.displayTitle = name
        self.value = value
    }
}
