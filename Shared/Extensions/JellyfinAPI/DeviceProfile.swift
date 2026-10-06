//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Defaults
import JellyfinAPI
import SwiftfinPlaybackProfiles
import SwiftfinStoredValues

extension DeviceProfile {
    @MainActor
    static func build(
        for videoPlayer: VideoPlayerType,
        compatibilityMode: PlaybackCompatibility,
        maxBitrate: Int? = nil,
        maxResolution: PlaybackResolution = Defaults[.VideoPlayer.Playback.appMaximumResolution]
    ) -> DeviceProfile {
        let settings = PlaybackProfileSettings(
            forceSubtitleBurnIn: StoredValues[.User.forceSubtitleBurnIn],
            customAction: Defaults[.VideoPlayer.Playback.customDeviceProfileAction],
            customProfiles: StoredValues[.User.customDeviceProfiles]
        )
        return build(
            for: videoPlayer,
            compatibilityMode: compatibilityMode,
            maxBitrate: maxBitrate,
            maxResolution: maxResolution,
            settings: settings,
            capabilities: PlaybackCapabilities.snapshot
        )
    }
}
