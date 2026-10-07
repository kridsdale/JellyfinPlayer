//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation
import os

/// Cancellation and callback delivery share one checked, exactly-once receipt.
final class PermissionReply: Sendable {
    private struct State: Sendable {
        var finished = false
        var continuation: CheckedContinuation<PermissionStatus, any Error>?
    }

    private let state = OSAllocatedUnfairLock(initialState: State())

    func install(_ continuation: CheckedContinuation<PermissionStatus, any Error>) -> Bool {
        let accepted = state.withLock { value in
            guard !value.finished else { return false }
            value.continuation = continuation
            return true
        }
        if !accepted {
            continuation.resume(throwing: CancellationError())
        }
        return accepted
    }

    func finish(_ result: Result<PermissionStatus, any Error>) {
        let continuation = state.withLock { value -> CheckedContinuation<PermissionStatus, any Error>? in
            guard !value.finished else { return nil }
            value.finished = true
            defer { value.continuation = nil }
            return value.continuation
        }
        continuation?.resume(with: result)
    }

    func cancel() {
        let continuation = state.withLock { value -> CheckedContinuation<PermissionStatus, any Error>? in
            guard !value.finished else { return nil }
            value.finished = true
            defer { value.continuation = nil }
            return value.continuation
        }
        continuation?.resume(throwing: CancellationError())
    }
}
