//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation

/// Owns publication relevance for caller-owned asynchronous operations. It does
/// not start or cancel tasks: checkpoints reject replaced, retired, released or
/// cancelled work immediately before local effects, including queued callbacks.
@MainActor
public final class AsyncOperationGate {
    public typealias Checkpoint = @MainActor @Sendable () throws -> Void
    private var generation: UUID?

    public init() {}

    /// Capture when the intent is submitted, before debounce or other scheduling.
    /// Callers should check task cancellation before replacing an existing intent.
    public func begin() -> Checkpoint {
        let ticket = UUID()
        generation = ticket
        return { [weak self] in
            try Task.checkCancellation()
            guard self?.generation == ticket else { throw CancellationError() }
        }
    }

    /// Invalidates all issued checkpoints. Already committed effects are not undone.
    public func cancel() {
        generation = nil
    }
}
