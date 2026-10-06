//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

// SPDX-License-Identifier: MPL-2.0
#if canImport(UIKit)
import MediaPlayer
import UIKit

/// MediaPlayer invokes this synchronous image provider on its own queue.
/// Capture only the SDK's immutable Sendable image, never an actor-owned model.
public enum NowPlayingArtwork {
    public static func make(_ image: UIImage) -> MPMediaItemArtwork {
        MPMediaItemArtwork(boundsSize: image.size) { @Sendable _ in image }
    }
}
#endif
