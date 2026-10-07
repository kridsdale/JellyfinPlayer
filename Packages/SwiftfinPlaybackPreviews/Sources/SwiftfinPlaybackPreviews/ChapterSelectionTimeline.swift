//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation

/// Selection for a chapter-list overlay, retaining the catalog's original order.
/// A chapter without a start can still be selected as the preceding entry. If no
/// later timestamp exists, the final entry is selected, including an unknown start.
/// Thumbnail lookup has a separate policy in ChapterPreviewTimeline.
public struct ChapterSelectionTimeline: Sendable {
    private let starts: [Duration?]

    /// Prepare once when the immutable chapter list is installed.
    public init(starts: [Duration?]) {
        self.starts = starts
    }

    /// Returns an index into the same original chapter list, or nil for an empty list.
    /// Before the first later entry, selection stays on its immediate predecessor
    /// (or entry zero). Neither the entries nor the playback time are normalized.
    public func index(at seconds: Duration) -> Int? {
        guard !starts.isEmpty else { return nil }
        guard let next = starts.firstIndex(where: { start in
            guard let start else { return false }
            return start > seconds
        }) else {
            return starts.count - 1
        }
        return max(0, next - 1)
    }
}
