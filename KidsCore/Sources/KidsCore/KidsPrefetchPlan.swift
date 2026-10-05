//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

// SPDX-License-Identifier: MPL-2.0
import Foundation

/// A finite plan derived only from the approved, displayed category. The caller
/// may warm these images and this show's verified episode list, never streams.
public struct KidsPrefetchPlan: Equatable, Sendable {
    public let artwork: [KidsItem]
    public let show: KidsItem?

    public static func make(
        focusedID: String?,
        category: KidsCategory,
        items: [KidsItem],
        binding: KidsBinding
    ) -> Self {
        let expected: KidsItem.Kind = category == .shows ? .series : .movie
        guard let focusedID, let index = items.firstIndex(where: { $0.id == focusedID }),
              items[index].kind == expected, KidsEligibility.permits(items[index], binding: binding)
        else {
            return Self(artwork: [], show: nil)
        }
        let neighbors = items[max(0, index - 1) ... min(items.count - 1, index + 1)]
        return Self(
            artwork: neighbors.filter {
                $0.kind == expected && KidsEligibility.permits($0, binding: binding) &&
                    !($0.imageTag ?? "").isEmpty && $0.imageOwnerID == $0.id
            },
            show: expected == .series ? items[index] : nil
        )
    }
}
