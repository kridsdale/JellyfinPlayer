//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

// SPDX-License-Identifier: MPL-2.0
import Foundation

/// Requests the compatible playback profile for the observed MPEG4-in-AVI
/// rendering failure. Unknown metadata and other formats retain their policy.
public enum KidsPlaybackCompatibilityPolicy: Sendable {
    public static func requiresCompatibleStream(videoCodec: String?, container: String?) -> Bool {
        guard let videoCodec, let container else { return false }
        return videoCodec.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "mpeg4"
            && container.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "avi"
    }
}
