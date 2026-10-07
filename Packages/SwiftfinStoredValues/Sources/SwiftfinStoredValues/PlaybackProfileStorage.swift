//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Defaults
import SwiftfinPlaybackProfiles

// Preserve the original JSON-based stored-value formats for existing installations.
extension AudioCodec: @retroactive Defaults.Serializable, Storable {}
extension VideoCodec: @retroactive Defaults.Serializable, Storable {}
extension MediaContainer: @retroactive Defaults.Serializable, Storable {}
extension SubtitleFormat: @retroactive Defaults.Serializable, Storable {}
extension PlaybackResolution: @retroactive Defaults.Serializable, Storable {}
extension CustomDeviceProfile: @retroactive Defaults.Serializable, Storable {}
extension CustomDeviceProfileAction: @retroactive Defaults.Serializable, Storable {}
extension VideoPlayerType: @retroactive Defaults.Serializable, Storable {}

// This enum previously used raw String storage rather than Codable JSON text.
// Adding Codable to its value model must not change installed defaults representation.
extension PlaybackCompatibility: @retroactive Defaults.Serializable, @retroactive Defaults.PreferRawRepresentable {}

// These existing preference values used JSON text before extraction.
extension PlaybackSpeed: @retroactive Defaults.Serializable, Storable {}
extension PlaybackBitrate: @retroactive Defaults.Serializable, Storable {}
extension MediaJumpInterval: @retroactive Defaults.Serializable, Storable {}
// The original test-size enum stored an Int, without a Codable bridge.
extension PlaybackBitrateTestSize: @retroactive Defaults.Serializable, @retroactive Defaults.PreferRawRepresentable {}
