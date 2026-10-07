//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation
import JellyfinAPI
import SwiftfinNetworking

public enum AccountQuickConnectEvent: Equatable, Sendable {
    case polling(code: String)
    case authenticated(secret: String)
}

public enum AccountQuickConnectError: Error, Equatable, Sendable {
    case retrievingCodeFailed
    case maxPollingHit
}

/// Internal scheduling port keeps the public API small and tests deterministic.
struct QuickConnectPollingPolicy: Sendable {
    let interval: Duration
    let maximumPolls: Int
    let failureTolerance: Int
    let sleep: @MainActor @Sendable (Duration) async throws -> Void
    init(
        interval: Duration = .seconds(5),
        maximumPolls: Int = 200,
        failureTolerance: Int = 5,
        sleep: @escaping @MainActor @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) {
        precondition(interval > .zero && maximumPolls > 0 && failureTolerance >= 0)
        self.interval = interval
        self.maximumPolls = maximumPolls
        self.failureTolerance = failureTolerance
        self.sleep = sleep
    }
}

public extension AccountAccessClient {
    /// Polling, UI delivery and the subsequent sign-in use this captured client.
    /// Cancellation or connection replacement prevents every follow-up request.
    func quickConnectEvents() -> AsyncThrowingStream<AccountQuickConnectEvent, any Error> {
        quickConnectEvents(policy: .init())
    }
}

extension AccountAccessClient {
    func quickConnectEvents(policy: QuickConnectPollingPolicy) -> AsyncThrowingStream<AccountQuickConnectEvent, any Error> {
        AsyncThrowingStream { continuation in
            let task = Task { @MainActor in
                do {
                    try await runQuickConnect(policy: policy) { event in
                        continuation.yield(event)
                    }
                    continuation.finish()
                } catch {
                    do {
                        try checkBinding()
                        continuation.finish(throwing: error)
                    } catch {
                        continuation.finish(throwing: error)
                    }
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func runQuickConnect(
        policy: QuickConnectPollingPolicy,
        yield: (AccountQuickConnectEvent) -> Void
    ) async throws {
        let initial = try await executor.value(for: Paths.initiateQuickConnect)
        guard let secret = initial.secret, let code = initial.code else {
            throw AccountQuickConnectError.retrievingCodeFailed
        }
        try checkBinding()
        yield(.polling(code: code))
        var consecutiveFailures = 0
        for _ in 0 ..< policy.maximumPolls {
            do {
                let state = try await executor.value(for: Paths.getQuickConnectState(secret: secret))
                if state.isAuthenticated == true, let authorizedSecret = state.secret {
                    try checkBinding()
                    yield(.authenticated(secret: authorizedSecret))
                    return
                }
                consecutiveFailures = 0
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                consecutiveFailures += 1
                guard consecutiveFailures <= policy.failureTolerance else { throw error }
            }
            try checkBinding()
            try await policy.sleep(policy.interval)
            try checkBinding()
        }
        throw AccountQuickConnectError.maxPollingHit
    }
}
