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
final class PokeIntervalTimer: ObservableObject, @MainActor Publisher {

    typealias Output = Void
    typealias Failure = Never

    private let defaultInterval: TimeInterval
    private let delaySubject = PassthroughSubject<Void, Never>()
    private var pendingTask: Task<Void, Never>?

    init(defaultInterval: TimeInterval = 5) {
        self.defaultInterval = defaultInterval.isFinite ? Swift.max(0, defaultInterval) : 5
    }

    isolated deinit {
        pendingTask?.cancel()
    }

    func receive<S: Subscriber>(subscriber: S) where S.Failure == Never, S.Input == Void {
        delaySubject.receive(subscriber: subscriber)
    }

    func poke(interval: TimeInterval? = nil) {
        stop()
        let requested = interval ?? defaultInterval
        let delay = requested.isFinite ? Swift.max(0, requested) : defaultInterval
        pendingTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: .seconds(delay))
                try Task.checkCancellation()
            } catch { return }
            guard let self else { return }
            self.pendingTask = nil
            self.delaySubject.send(())
        }
    }

    func stop() {
        pendingTask?.cancel()
        pendingTask = nil
    }
}
