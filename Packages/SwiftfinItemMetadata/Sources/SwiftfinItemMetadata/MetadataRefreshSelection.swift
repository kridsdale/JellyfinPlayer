//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import JellyfinAPI

public enum MetadataRefreshSelection: CaseIterable, Hashable, Sendable {
    case scan
    case missing
    case all

    public var replaceMetadata: Bool {
        switch self {
        case .scan, .missing:
            false
        case .all:
            true
        }
    }

    public var metadataRefreshMode: MetadataRefreshMode {
        switch self {
        case .scan:
            .default
        case .missing, .all:
            .fullRefresh
        }
    }

    public func replaceElements(_ selection: Bool) -> Bool {
        switch self {
        case .scan:
            false
        case .missing, .all:
            selection
        }
    }
}
