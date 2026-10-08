//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import JellyfinAPI

/// Immutable requested choices. Stream resolution and account authority belong
/// to playback preparation; this value never reads defaults or a live player.
public struct PlaybackOptions: Sendable {
    public enum Selection: Sendable {
        case mediaSource(MediaSourceInfo?)
        case audioStreamIndex(Int?)
        case subtitleStreamIndex(Int?)
        case bitrate(PlaybackBitrate)
    }

    public let mediaSource: MediaSourceInfo?
    public let audioStreamIndex: Int?
    public let subtitleStreamIndex: Int?
    public let requestedBitrate: PlaybackBitrate

    public init(
        mediaSource: MediaSourceInfo? = nil,
        audioStreamIndex: Int? = nil,
        subtitleStreamIndex: Int? = nil,
        requestedBitrate: PlaybackBitrate
    ) {
        self.mediaSource = mediaSource
        self.audioStreamIndex = audioStreamIndex
        self.subtitleStreamIndex = subtitleStreamIndex
        self.requestedBitrate = requestedBitrate
    }

    /// Selecting a source resets source-specific tracks, including when the
    /// same source is selected again. Other choices preserve unrelated fields.
    public func selecting(_ selection: Selection) -> Self {
        var mediaSource = mediaSource
        var audioStreamIndex = audioStreamIndex
        var subtitleStreamIndex = subtitleStreamIndex
        var requestedBitrate = requestedBitrate
        switch selection {
        case let .mediaSource(source):
            mediaSource = source
            audioStreamIndex = nil
            subtitleStreamIndex = nil
        case let .audioStreamIndex(index):
            audioStreamIndex = index
        case let .subtitleStreamIndex(index):
            subtitleStreamIndex = index
        case let .bitrate(bitrate):
            requestedBitrate = bitrate
        }
        return Self(
            mediaSource: mediaSource,
            audioStreamIndex: audioStreamIndex,
            subtitleStreamIndex: subtitleStreamIndex,
            requestedBitrate: requestedBitrate
        )
    }
}
