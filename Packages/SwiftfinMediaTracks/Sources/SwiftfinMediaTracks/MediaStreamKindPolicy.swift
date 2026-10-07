//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import JellyfinAPI

/// Raw item streams include external tracks. Playback policy owns its exclusions.
public enum MediaStreamKindPolicy {
    public static func streams(in streams: [MediaStream]?, matching kind: MediaStreamType) -> [MediaStream] {
        streams?.filter { $0.type == kind } ?? []
    }
}
