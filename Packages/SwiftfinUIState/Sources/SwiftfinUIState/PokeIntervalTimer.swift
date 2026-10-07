//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Combine
import Foundation

/// A one-shot UI timer. Poking replaces the pending deadline; cancellation and
/// delivery stay on the same actor, and the pending task never retains its owner.
@MainActor
public final class PokeIntervalTimer: ObservableObject, @MainActor Publisher {

    public typealias Output = Void
    public typealias Failure = Never

    private let defaultInterval: TimeInterval
    private let sleep: @Sendable (Duration) async throws -> Void
    private let delaySubject = PassthroughSubject<Void, Never>()
    private var pendingTask: Task<Void, Never>?

    public convenience init(defaultInterval: TimeInterval = 5) {
        self.init(defaultInterval: defaultInterval, sleep: { try await Task.sleep(for: $0) })
    }

    // The test port controls deadlines without depending on wall-clock scheduling.
    init(defaultInterval: TimeInterval, sleep: @escaping @Sendable (Duration) async throws -> Void) {
        self.defaultInterval = defaultInterval.isFinite ? Swift.max(0, defaultInterval) : 5
        self.sleep = sleep
    }

    isolated deinit {
        pendingTask?.cancel()
    }

    public func receive<S: Subscriber>(subscriber: S) where S.Failure == Never, S.Input == Void {
        delaySubject.receive(subscriber: subscriber)
    }

    public func poke(interval: TimeInterval? = nil) {
        stop()
        let requested = interval ?? defaultInterval
        let delay = requested.isFinite ? Swift.max(0, requested) : defaultInterval
        let sleep = self.sleep
        pendingTask = Task { @MainActor [weak self] in
            do {
                try await sleep(.seconds(delay))
                try Task.checkCancellation()
            } catch { return }
            guard let self else { return }
            self.pendingTask = nil
            self.delaySubject.send(())
        }
    }

    public func stop() {
        pendingTask?.cancel()
        pendingTask = nil
    }
}
