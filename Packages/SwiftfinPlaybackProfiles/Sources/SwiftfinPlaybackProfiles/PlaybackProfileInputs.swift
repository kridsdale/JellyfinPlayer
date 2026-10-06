//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

/// Immutable current hardware/policy values. No device APIs or defaults are read by profile assembly.
public struct PlaybackCapabilitySnapshot: Equatable, Sendable {
    public let supportsAV1: Bool
    public let supportsHEVC: Bool
    public let supportsVP9: Bool
    public let supportsHLG: Bool
    public let supportsHDR10: Bool
    public let supportsDolbyVision: Bool
    public let hdrEnabled: Bool
    public init(
        supportsAV1: Bool = false,
        supportsHEVC: Bool = false,
        supportsVP9: Bool = false,
        supportsHLG: Bool = false,
        supportsHDR10: Bool = false,
        supportsDolbyVision: Bool = false,
        hdrEnabled: Bool = false
    ) {
        self.supportsAV1 = supportsAV1
        self.supportsHEVC = supportsHEVC
        self.supportsVP9 = supportsVP9
        self.supportsHLG = supportsHLG
        self.supportsHDR10 = supportsHDR10
        self.supportsDolbyVision = supportsDolbyVision
        self.hdrEnabled = hdrEnabled
    }
}

public struct PlaybackProfileSettings: Equatable, Sendable {
    public let forceSubtitleBurnIn: Bool
    public let customAction: CustomDeviceProfileAction
    public let customProfiles: [CustomDeviceProfile]
    public init(
        forceSubtitleBurnIn: Bool = false,
        customAction: CustomDeviceProfileAction = .add,
        customProfiles: [CustomDeviceProfile] = []
    ) {
        self.forceSubtitleBurnIn = forceSubtitleBurnIn
        self.customAction = customAction
        self.customProfiles = customProfiles
    }
}
