//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

// SPDX-License-Identifier: MPL-2.0
import Foundation
import KidsDiagnostics

/// Main-actor ingress preserves start/progress/stop order. One async worker
/// sends requests serially; a single pending slot keeps the latest progress
/// under a slow network, while finish closes ingress with an undroppable stop.
/// Each instance belongs to one immutable playback/account identity.
@MainActor
public final class KidsPlaybackReporter<Snapshot: Sendable> {
    public enum Kind: Sendable, Equatable { case start, progress, stop }
    public struct Event: Sendable {
        public let kind: Kind
        public let snapshot: Snapshot
    }

    private enum Update: Sendable { case progress(Snapshot), stop(Snapshot) }
    private let continuation: AsyncStream<Update>.Continuation
    private let worker: Task<Void, Never>
    private var ended = false

    public init(
        initial: Snapshot,
        after previous: KidsPlaybackReporter<Snapshot>? = nil,
        send: @escaping @Sendable (Event) async throws -> Void
    ) {
        let channel = AsyncStream<Update>.makeStream(bufferingPolicy: .bufferingNewest(1))
        continuation = channel.continuation
        let predecessor = previous?.worker
        worker = Task.detached(priority: .utility) {
            // Reporting is chained across videos without blocking the player.
            // A delayed old stop must complete before the next start; Jellyfin
            // clears device NowPlaying state when it processes a stop report.
            await predecessor?.value
            func attempt(_ kind: Kind, _ snapshot: Snapshot) async -> Bool {
                guard !Task.isCancelled else { return false }
                do {
                    try await send(Event(kind: kind, snapshot: snapshot))
                    return !Task.isCancelled
                } catch { return false }
            }
            var started = await attempt(.start, initial)
            for await update in channel.stream {
                guard !Task.isCancelled else { return }
                switch update {
                case let .progress(snapshot):
                    if started {
                        _ = await attempt(.progress, snapshot)
                    } else {
                        // Retry a failed start only when a new report arrives.
                        // Never spin, overlap requests or send progress before start.
                        started = await attempt(.start, snapshot)
                    }
                case let .stop(snapshot):
                    if !started {
                        started = await attempt(.start, snapshot)
                    }
                    if started {
                        _ = await attempt(.stop, snapshot)
                    }
                    return
                }
            }
        }
    }

    public func update(_ snapshot: Snapshot) {
        guard !ended else { return }
        continuation.yield(.progress(snapshot))
    }

    public func finish(_ snapshot: Snapshot) {
        guard !ended else { return }
        ended = true
        continuation.yield(.stop(snapshot))
        continuation.finish()
    }

    public func cancel() {
        ended = true
        continuation.finish()
        worker.cancel()
    }

    public func waitUntilFinished() async {
        await worker.value
    }

    deinit { continuation.finish() }
}
