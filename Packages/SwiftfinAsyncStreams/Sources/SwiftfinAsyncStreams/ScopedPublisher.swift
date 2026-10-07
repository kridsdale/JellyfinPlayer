//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Combine
import Foundation

/// Owns one account/connection-scoped subscription and its queued UI receipts.
/// Replacing or cancelling the scope invalidates receipts before retiring the
/// previous source. Publishers may emit on any executor; delivery always enters
/// the main actor. Callers provide identity/currentness and capture UI weakly.
@MainActor
public final class ScopedPublisher<Scope: Hashable & Sendable, Value: Sendable> {
    typealias Delivery = @MainActor @Sendable () -> Void
    typealias Scheduler = @Sendable (@escaping Delivery) -> Void

    private let schedule: Scheduler
    private var scope: Scope?
    private var generation = UUID()
    private var subscription: AnyCancellable?
    private var isCurrent: (@MainActor @Sendable () -> Bool)?
    private var receive: (@MainActor @Sendable (Value) -> Void)?

    public init() {
        schedule = { delivery in Task { @MainActor in delivery() } }
    }

    // Inject scheduling only for deterministic native queue/lifetime contracts.
    init(schedule: @escaping Scheduler) {
        self.schedule = schedule
    }

    /// Returns true only when this call installed a changed, still-current scope.
    /// Repeated identities reuse the subscription but update publication hooks.
    @discardableResult
    public func replace(
        scope: Scope,
        makePublisher: @MainActor () -> AnyPublisher<Value, Never>,
        isCurrent: @escaping @MainActor @Sendable () -> Bool,
        receive: @escaping @MainActor @Sendable (Value) -> Void
    ) -> Bool {
        if self.scope == scope {
            self.isCurrent = isCurrent
            self.receive = receive
            return false
        }
        let ticket = UUID()
        let previous = subscription
        generation = ticket
        self.scope = scope
        subscription = nil
        self.isCurrent = isCurrent
        self.receive = receive
        previous?.cancel()
        guard generation == ticket else { return false }
        let publisher = makePublisher()
        guard generation == ticket else { return false }
        let candidate = Self.subscribe(publisher, schedule: schedule) { [weak self] value in
            self?.deliver(value, generation: ticket)
        }
        guard generation == ticket else {
            candidate.cancel()
            return false
        }
        subscription = candidate
        return true
    }

    /// Logout and owner teardown revoke pending delivery even if source cleanup
    /// emits again. Reentrant cleanup cannot retire a subsequently installed scope.
    public func cancel() {
        let previous = subscription
        generation = UUID()
        scope = nil
        subscription = nil
        isCurrent = nil
        receive = nil
        previous?.cancel()
    }

    private func deliver(_ value: Value, generation ticket: UUID) {
        guard generation == ticket else { return }
        let current = isCurrent?() ?? false
        guard generation == ticket else { return }
        guard current else {
            cancel()
            return
        }
        receive?(value)
    }

    // The raw Combine callback is created outside actor isolation so foreign
    // emission has no inherited executor assertion. Only Sendable values queue.
    private nonisolated static func subscribe(
        _ publisher: AnyPublisher<Value, Never>,
        schedule: @escaping Scheduler,
        receive: @escaping @MainActor @Sendable (Value) -> Void
    ) -> AnyCancellable {
        publisher.sink { value in schedule { receive(value) } }
    }

    isolated deinit { subscription?.cancel() }
}
