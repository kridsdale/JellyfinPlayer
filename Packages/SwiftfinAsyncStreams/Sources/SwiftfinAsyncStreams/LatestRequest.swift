//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation

/// Owns one replaceable asynchronous value request on the UI actor.
/// Cancelled, superseded and failed requests never publish. Inputs and publication
/// belong to the caller; callbacks should capture their presentation owner weakly.
@MainActor
public final class LatestRequest<Value: Sendable> {
    private var generation: UUID?
    private var task: Task<Void, Never>?

    public init() {}

    public func replace(
        operation: @escaping @MainActor @Sendable () async throws -> Value,
        receive: @escaping @MainActor @Sendable (Value) -> Void
    ) {
        cancel()
        let generation = UUID()
        self.generation = generation
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
            }
        }
    }

    /// Invalidates publication immediately, even if the operation ignores cancellation.
    public func cancel() {
        generation = nil
        task?.cancel()
        task = nil
    }

    isolated deinit {
        task?.cancel()
    }
}
