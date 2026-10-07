//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation

public enum MPVPlaybackTrackKind: Sendable, Equatable { case video, audio, subtitle }

public struct MPVPlaybackTrack: Sendable, Equatable {
    public let index: Int
    public let kind: MPVPlaybackTrackKind
    public let title: String?
    public let external: Bool
    public let selected: Bool
    public init(index: Int, kind: MPVPlaybackTrackKind, title: String? = nil, external: Bool = false, selected: Bool = false) {
        self.index = index
        self.kind = kind
        self.title = title
        self.external = external
        self.selected = selected
    }
}

public struct MPVPlaybackFailure: Error, LocalizedError, Sendable, Equatable, CustomStringConvertible, CustomDebugStringConvertible {
    public let message: String
    public init(message: String) {
        self.message = message
    }

    public var errorDescription: String? {
        message
    }

    public var description: String {
        "MPVPlaybackFailure(redacted)"
    }

    public var debugDescription: String {
        description
    }
}

public enum MPVPlaybackPhase: Sendable, Equatable {
    case idle
    case loading
    case ready
    case playing
    case paused
    case buffering
    case seeking
    case ended
    case stopped
    case failed(MPVPlaybackFailure)
    public var transient: Bool {
        self == .loading || self == .buffering || self == .seeking
    }

    public var acceptsTracks: Bool {
        switch self { case .ready, .playing, .paused, .buffering, .seeking: true
        default: false }
    }
}

public struct MPVPlaybackFrame: Sendable, Equatable, CustomStringConvertible, CustomDebugStringConvertible {
    public var phase: MPVPlaybackPhase = .idle
    public var time: Duration = .zero
    public var sourceURL: URL?
    public var videoSize: CGSize?
    public var subtitleVideoSize: CGSize?
    public var tracks: [MPVPlaybackTrack] = []
    public init() {}
    public var description: String {
        "MPVPlaybackFrame(redacted)"
    }

    public var debugDescription: String {
        description
    }
}

public struct MPVSidecarSubtitle: Sendable {
    public let jellyfinIndex: Int?
    public let url: URL
    public init(jellyfinIndex: Int?, url: URL) {
        self.jellyfinIndex = jellyfinIndex
        self.url = url
    }
}

/// An already authorized URL and immutable per-item options, supplied by the host.
public struct MPVPlaybackRequest: Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    public let url: URL
    public let start: Duration?
    public let autoPlay: Bool
    public let rate: Float
    public let sidecars: [MPVSidecarSubtitle]
    public init(url: URL, start: Duration?, autoPlay: Bool, rate: Float, sidecars: [MPVSidecarSubtitle]) {
        self.url = url
        self.start = start.map { max(.zero, $0) }
        self.autoPlay = autoPlay
        self.rate = rate
        self.sidecars = sidecars
    }

    public var description: String {
        "MPVPlaybackRequest(redacted)"
    }

    public var debugDescription: String {
        description
    }
}
