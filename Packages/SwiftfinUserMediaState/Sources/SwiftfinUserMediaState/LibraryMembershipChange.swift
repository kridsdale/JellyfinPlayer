//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation
import JellyfinAPI

/// A library's membership response, independent of its view model or scheduler.
public enum LibraryMembershipChange: Sendable, Equatable {
    case none
    case remove(itemID: String)
    case refresh(minimumInterval: TimeInterval)
}

public extension UserMediaStatePolicy {
    static func nextUpChange(for data: UserItemDataDto, isLoaded: Bool) -> LibraryMembershipChange {
        guard data.itemID != nil else { return .none }
        if isLoaded {
            return .refresh(minimumInterval: 3)
        }
        guard (data.playbackPositionTicks ?? 0) > 0 || data.isPlayed != nil else { return .none }
        return .refresh(minimumInterval: 30)
    }

    static func resumeChange(for data: UserItemDataDto, isLoaded: Bool) -> LibraryMembershipChange {
        guard let itemID = data.itemID else { return .none }
        if data.isPlayed == true {
            return .remove(itemID: itemID)
        }
        guard !isLoaded, (data.playbackPositionTicks ?? 0) > 0 else { return .none }
        return .refresh(minimumInterval: 30)
    }
}
