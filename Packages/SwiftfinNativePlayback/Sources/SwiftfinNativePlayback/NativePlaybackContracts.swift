//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation

/// Already-authorized media. The host owns account, catalog and settings policy.
public struct NativePlaybackRequest: Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    public let url: URL
    public let start: Duration
    public let live: Bool
    public let title: String
    public let subtitle: String?
    public let overview: String?
    public init(
        url: URL,
        start: Duration = .zero,
        live: Bool = false,
        title: String,
        subtitle: String? = nil,
        overview: String? = nil
    ) {
        self.url = url
        self.start = max(.zero, start)
        self.live = live
        self.title = title
        self.subtitle = subtitle
        self.overview = overview
    }

    public var description: String {
        "NativePlaybackRequest(<redacted>)"
    }

    public var debugDescription: String {
        description
    }
}

public enum NativePlaybackState: Sendable, Equatable { case paused, waiting, playing }
public enum NativePlaybackEvent: Sendable, Equatable {
    case clock(Duration)
    case state(NativePlaybackState)
    case resumePosition(Duration)
    case naturalEnd
    case playbackFailed
}
