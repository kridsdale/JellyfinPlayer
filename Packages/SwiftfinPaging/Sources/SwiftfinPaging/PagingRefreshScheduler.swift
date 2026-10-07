//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation

/// A canceled delayed refresh does not retain its owner or mark a refresh complete.
@MainActor
public final class PagingRefreshScheduler {
    public typealias Now = @MainActor @Sendable () -> Duration
    public typealias Sleep = @Sendable (Duration) async throws -> Void
    private let now: Now
    private let sleep: Sleep
    private var task: Task<Void, Never>?
    private var generation = UUID()
    private var lastRefresh: Duration?
    public init(
        now: @escaping Now = { .seconds(ProcessInfo.processInfo.systemUptime) },
        sleep: @escaping Sleep = { try await Task.sleep(for: $0) }
    ) {
        self.now = now
        self.sleep = sleep
    }

    isolated deinit { task?.cancel() }

    @discardableResult
    public func schedule(
        debounce: Duration = .milliseconds(350),
        minimumInterval: Duration = .seconds(5),
        refresh: @escaping @MainActor @Sendable () async -> Void
    ) -> Bool {
        if let lastRefresh, now() - lastRefresh < max(.zero, minimumInterval) {
            return false
        }
        cancel()
        let epoch = generation, sleep = self.sleep
        task = Task { [weak self] in
            do {
                if debounce > .zero {
                    try await sleep(debounce)
                }
            } catch { return }
            guard !Task.isCancelled, let self, generation == epoch else { return }
            await refresh()
            guard !Task.isCancelled, generation == epoch else { return }
            lastRefresh = now()
            task = nil
        }
        return true
    }

    public func cancel() {
        generation = UUID()
        task?.cancel()
        task = nil
    }
}
