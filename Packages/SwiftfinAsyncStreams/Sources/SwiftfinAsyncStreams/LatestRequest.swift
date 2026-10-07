//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation

/// Owns one replaceable asynchronous value request on the UI actor.
/// Cancelled and superseded requests never publish values or errors. A current
/// failure may reach the optional failure callback. Synchronous begin/publication
/// belong to the caller; callbacks should capture their presentation owner weakly.
@MainActor
public final class LatestRequest<Value: Sendable> {
    private var generation: UUID?
    private var task: Task<Void, Never>?

    public init() {}

    public func replace(
        operation: @escaping @MainActor @Sendable () async throws -> Value,
        begin: @MainActor @Sendable () -> Void = {},
        failure: @escaping @MainActor @Sendable (any Error) -> Void = { _ in },
        receive: @escaping @MainActor @Sendable (Value) -> Void
    ) {
        guard !Task.isCancelled else { return }
        let generation = UUID()
        let previous = task
        self.generation = generation
        task = nil
        previous?.cancel()
        guard self.generation == generation else { return }
        begin()
        guard self.generation == generation else { return }
        task = Task { [weak self] in
            do {
                try Task.checkCancellation()
                let value = try await operation()
                try Task.checkCancellation()
                guard let self, self.generation == generation else { return }
                self.task = nil
                self.generation = nil
                receive(value)
            } catch {
                guard let self, self.generation == generation else { return }
                self.task = nil
                self.generation = nil
                guard !Task.isCancelled, !(error is CancellationError), (error as? URLError)?.code != .cancelled else { return }
                failure(error)
            }
        }
    }

    /// Waits for the request owned at entry, even if a later request replaces it.
    public func waitUntilFinished() async {
        let pending = task
        await pending?.value
    }

    /// Invalidates publication immediately, even if the operation ignores cancellation.
    public func cancel() {
        let previous = task
        generation = nil
        task = nil
        previous?.cancel()
    }

    isolated deinit {
        task?.cancel()
    }
}
