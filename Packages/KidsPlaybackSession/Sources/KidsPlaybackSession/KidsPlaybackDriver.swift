//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Combine
import Foundation
import KidsDiagnostics
import KidsDomain

/// A value snapshot of decoded output. SDK players and their state never cross this port.
public struct KidsPlaybackFrame: Sendable {
    public var seconds = 0.0
    public var paused = false
    public var playing = false
    public var buffering = false
    public var preparing = false
    public var applyingStartPosition = false
    public var failed = false
    public var terminal = false
    public var reachedEnd = false
    public var displayedPictures = 0
    public var seekable = false
    public init() {}
}

/// Driver events are emitted on the main actor, including SDK error callbacks.
public enum KidsPlaybackFailure: Error, Sendable {
    case authentication
    case stream
}

public enum KidsPlaybackDriverEvent: Sendable {
    case updated
    case transport(paused: Bool, seconds: Double, terminal: Bool)
    case failure(KidsPlaybackFailure)
    case naturalEnd
}

@MainActor
public protocol KidsPlaybackDriver: AnyObject {
    var frame: KidsPlaybackFrame { get }
    var events: AnyPublisher<KidsPlaybackDriverEvent, Never> { get }
    func start()
    func beginReporting()
    func togglePlayPause()
    func pause()
    func seek(seconds: Double)
    func stop() async
}

/// Application callbacks own authorization, persistence and title selection.
@MainActor
public protocol KidsPlaybackSessionDelegate: AnyObject {
    var isPreview: Bool { get }
    func playbackBegan(_ session: KidsPlaybackController)
    func playbackCheckpoint(_ session: KidsPlaybackController, seconds: Double)
    func completed(_ session: KidsPlaybackController) async
    func continuePlayback(_ session: KidsPlaybackController) async
    func stopPlaybackFromSession() async
    func retryPlayback(_ session: KidsPlaybackController, position: Double)
    func playbackFailed(_ session: KidsPlaybackController, error: KidsPlaybackFailure)
}

@MainActor
public protocol KidsPlaybackSessionFactory: AnyObject {
    func prepare(
        item: KidsItem,
        title: KidsItem,
        mode: KidsPlaybackMode,
        position: Double,
        episodes: [KidsItem],
        delegate: any KidsPlaybackSessionDelegate,
        performance: KidsPerformanceSpan?,
        simulateStreamFailure: Bool
    ) async throws -> KidsPlaybackController
}
