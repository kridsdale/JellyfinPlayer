//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation

/// Pure geometry; no UI, settings, account or native observation references.
public enum ScrollCentering {
    public static func offset(target: CGFloat, viewport: CGFloat, content: CGFloat) -> CGFloat? {
        guard target.isFinite, viewport.isFinite, content.isFinite,
              viewport > 0, content > viewport else { return nil }
        return min(max(target - viewport / 2, 0), content - viewport)
    }
}
