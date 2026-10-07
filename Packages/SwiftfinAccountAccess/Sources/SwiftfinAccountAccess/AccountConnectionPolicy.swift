//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation

public enum AccountConnectionPolicy {
    /// A public-info response may redirect to a different origin/base path.
    /// Only a response ending in that endpoint can supply a replacement base.
    public static func redirectedURL(initial: URL, response: URL?) -> URL {
        guard let response, var components = URLComponents(url: response, resolvingAgainstBaseURL: false),
              components.path.hasSuffix("/System/Info/Public") else { return initial }
        components.path.removeLast("/System/Info/Public".count)
        components.query = nil
        components.fragment = nil
        components.user = nil
        components.password = nil
        return components.url ?? initial
    }
}
