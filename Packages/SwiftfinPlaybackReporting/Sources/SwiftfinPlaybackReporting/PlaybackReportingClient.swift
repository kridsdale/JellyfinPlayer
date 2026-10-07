//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

// SPDX-License-Identifier: MPL-2.0
import Foundation
import JellyfinAPI
import SwiftfinAsyncStreams
import SwiftfinNetworking

public enum PlaybackReportingError: Error, Sendable { case identityChanged }

/// Values belong to the original playback session even after the UI changes
/// account. Queued terminal cleanup must reach that captured transport.
public struct PlaybackReportIdentity: Equatable, Sendable {
    public let itemID: String
    public let mediaSourceID: String?
    public let liveStreamID: String?
    public let playSessionID: String
    public let sessionID: String?
    public let canSeek: Bool?
    public let playMethod: PlayMethod?
    public init(
        itemID: String,
        mediaSourceID: String?,
        liveStreamID: String?,
        playSessionID: String,
        sessionID: String? = nil,
        canSeek: Bool? = nil,
        playMethod: PlayMethod? = nil
    ) {
        self.itemID = itemID
        self.mediaSourceID = mediaSourceID
        self.liveStreamID = liveStreamID
        self.playSessionID = playSessionID
        self.sessionID = sessionID
        self.canSeek = canSeek
        self.playMethod = playMethod
    }

    public func snapshot(positionTicks: Int?, audio: Int?, subtitle: Int?, isPaused: Bool? = nil) -> PlaybackStateInfo {
        PlaybackStateInfo(
            audioStreamIndex: audio,
            canSeek: canSeek,
            isPaused: isPaused,
            itemID: itemID,
            liveStreamID: liveStreamID,
            mediaSourceID: mediaSourceID,
            playMethod: playMethod,
            playSessionID: playSessionID,
            positionTicks: positionTicks,
            sessionID: sessionID,
            subtitleStreamIndex: subtitle
        )
    }

    public func accepts(_ snapshot: PlaybackStateInfo) -> Bool {
        snapshot.itemID == itemID && snapshot.mediaSourceID == mediaSourceID && snapshot.liveStreamID == liveStreamID
            && snapshot.playSessionID == playSessionID && snapshot.sessionID == sessionID
    }
}

@MainActor
public final class PlaybackReportingClient {
    private let sender: any JellyfinRequestSending
    public let identity: PlaybackReportIdentity
    public init(sender: any JellyfinRequestSending, identity: PlaybackReportIdentity) {
        self.sender = sender
        self.identity = identity
    }

    public func send(
        _ kind: PlaybackReportQueue<PlaybackStateInfo>.Kind,
        snapshot: PlaybackStateInfo,
        delegate: (any URLSessionDataDelegate)? = nil
    ) async throws {
        try Task.checkCancellation()
        guard identity.accepts(snapshot) else { throw PlaybackReportingError.identityChanged }
        switch kind {
        case .start: try await sender.complete(Paths.reportPlaybackStart(snapshot), delegate: delegate)
        case .progress: try await sender.complete(Paths.reportPlaybackProgress(snapshot), delegate: delegate)
        case .stop:
            let stop = PlaybackStopInfo(
                itemID: identity.itemID,
                liveStreamID: identity.liveStreamID,
                mediaSourceID: identity.mediaSourceID,
                playSessionID: identity.playSessionID,
                positionTicks: snapshot.positionTicks,
                sessionID: identity.sessionID
            )
            try await sender.complete(Paths.reportPlaybackStopped(stop), delegate: delegate)
        }
        try Task.checkCancellation()
    }
}
