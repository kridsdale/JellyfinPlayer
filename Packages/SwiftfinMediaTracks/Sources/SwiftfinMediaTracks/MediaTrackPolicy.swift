//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation
import JellyfinAPI
import SwiftfinPlaybackProfiles

/// Immutable policy inputs capture the mode that produced this item's device profile.
public struct MediaTrackPolicy: Sendable {
    private let mediaSource: MediaSourceInfo
    private let deviceProfile: DeviceProfile
    public let audioStreams: [MediaStream]
    public let subtitleStreams: [MediaStream]
    public let videoStreams: [MediaStream]
    public let selectedAudioIndex: Int
    public let selectedSubtitleIndex: Int
    public let initialIndexMap: MediaTrackIndexMap
    public init(
        mediaSource: MediaSourceInfo,
        deviceProfile: DeviceProfile,
        compatibility: PlaybackCompatibility,
        audioIndex: Int? = nil,
        subtitleIndex: Int? = nil
    ) {
        self.mediaSource = mediaSource
        self.deviceProfile = deviceProfile
        let streams = mediaSource.mediaStreams ?? []
        audioStreams = streams.filter { $0.type == .audio && $0.isExternal != true }
        subtitleStreams = streams.filter {
            $0.type == .subtitle && $0.deliveryMethod != .drop &&
                !(compatibility == .directPlay && $0.isExternal == true && $0.isTextSubtitleStream != true)
        }
        videoStreams = streams.filter { $0.type == .video }
        selectedAudioIndex = audioIndex ?? mediaSource.defaultAudioStreamIndex ?? streams.first(where: { $0.type == .audio })?.index ?? 0
        selectedSubtitleIndex = subtitleIndex ?? mediaSource.defaultSubtitleStreamIndex ?? -1
        initialIndexMap = MediaTrackIndexMap.build(
            from: streams,
            for: mediaSource.transcodingURL == nil ? .directPlay : .transcode,
            selectedAudioStreamIndex: selectedAudioIndex
        )
    }

    public func requiresRebuild(type: MediaStreamType, from oldIndex: Int?, to newIndex: Int?) -> Bool {
        let isTranscoding = mediaSource.transcodingURL != nil

        // Disabling a track is ALWAYS a local-only operation.
        guard let newIndex, newIndex != -1 else { return false }

        switch type {
        case .audio:

            // Transcodes contain a single audio track and MUST rebuild.
            if isTranscoding {
                return true
            }

            guard let newStream = audioStreams.first(where: { $0.index == newIndex }) else { return true }

            // TODO: When audio playback exists then get the type dynamically.
            return !deviceProfile.canPlay(
                type: .video,
                audioCodec: newStream.codec,
                container: mediaSource.container
            )

        case .subtitle:
            // Optional (do not guard) since this could be -1 for disabled.
            let oldStream = oldIndex.flatMap { idx in subtitleStreams.first { $0.index == idx } }

            // Transitioning away from encoded subtitles always requires a rebuild so the server stops burning them into the video.
            if oldStream?.deliveryMethod == .encode {
                return true
            }

            // Catch if the new stream doesn't exist. If non-existent this will fallback to -1 and disable locally.
            guard let newStream = subtitleStreams.first(where: { $0.index == newIndex }) else { return false }

            if newStream.isExternal == true {

                // External subtitles can only be loaded as sidecars when the profile allows external or HLS delivery for the format.
                // E.G, This should disable external PGS for VLC since VLC cannot play them.
                return !(deviceProfile.canPlay(subtitleFormat: newStream.codec, method: .external)
                    || deviceProfile.canPlay(subtitleFormat: newStream.codec, method: .hls))
            }

            // Embedded subtitles are in the source container.
            // Only reachable while direct-playing AND when the profile supports embed delivery.
            return isTranscoding || !deviceProfile.canPlay(subtitleFormat: newStream.codec, method: .embed)

        default:
            return false
        }
    }
}
