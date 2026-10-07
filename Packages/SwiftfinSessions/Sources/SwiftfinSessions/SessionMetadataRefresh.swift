//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

// Swiftfin is subject to the Mozilla Public License, v2.0.
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
import Foundation
import SwiftfinAsyncStreams

/// Scoped metadata freshness and one replaceable refresh. Scope values should be
/// immutable account/binding identifiers, never native resources or credentials.
/// Freshness is process-local: an unidentified historic global stamp is not trusted.
@MainActor
public final class SessionMetadataRefresh<Scope: Hashable & Sendable> {
    public typealias Checkpoint = @MainActor @Sendable () throws -> Void
    private enum Outcome: Sendable {
        case completed
        case failed(any Error)
        case cancelled
    }

    private struct Success {
        let date: Date
        let ordinal: UInt64
    }

    private let requestOwner = LatestRequest<Outcome>()
    private let maximumAge: TimeInterval
    private let capacity: Int
    private let now: @MainActor @Sendable () -> Date
    private var successes: [Scope: Success] = [:]
    private var ordinal: UInt64 = 0
    private var generation: UUID?
    private var activeScope: Scope?
    private var activeBinding: (@MainActor @Sendable () -> Bool)?

    public init(
        maximumAge: TimeInterval = 24 * 60 * 60,
        capacity: Int = 16,
        now: @escaping @MainActor @Sendable () -> Date = { .now }
    ) {
        self.maximumAge = maximumAge.isFinite ? max(0, maximumAge) : 24 * 60 * 60
        self.capacity = max(1, capacity)
        self.now = now
    }

    /// Returns whether work was scheduled. The operation must call its checkpoint
    /// immediately before local effects after each await; cancellation cannot undo
    /// an effect already committed by a noncooperating operation.
    @discardableResult
    public func request(
        scope: Scope,
        force: Bool = false,
        isCurrent: @escaping @MainActor @Sendable () -> Bool,
        operation: @escaping @MainActor @Sendable (@escaping Checkpoint) async throws -> Void,
        didRefresh: @escaping @MainActor @Sendable (Date) -> Void = { _ in },
        didFail: @escaping @MainActor @Sendable (any Error) -> Void = { _ in }
    ) -> Bool {
        if !force, activeScope == scope, let activeBinding {
            let existing = generation
            let current = activeBinding()
            guard generation == existing else { return false }
            if current, existing != nil {
                return false
            }
        }
        let attempt = UUID()
        generation = attempt
        activeScope = nil
        activeBinding = nil
        requestOwner.cancel()
        guard isCurrent(), generation == attempt else { return false }
        let date = now()
        guard generation == attempt else { return false }
        if !force, let success = successes[scope], date.timeIntervalSince(success.date) <= maximumAge {
            generation = nil
            return false
        }
        let checkpoint: Checkpoint = { [weak self] in
            try Task.checkCancellation()
            guard let self, isCurrent(), self.generation == attempt else { throw CancellationError() }
        }
        activeScope = scope
        activeBinding = isCurrent
        requestOwner.replace(operation: {
            do {
                try checkpoint()
                try await operation(checkpoint)
                try checkpoint()
                return .completed
            } catch is CancellationError {
                return .cancelled
            } catch {
                guard (try? checkpoint()) != nil else { return .cancelled }
                return .failed(error)
            }
        }, receive: { [weak self] outcome in
            guard let self, self.generation == attempt else { return }
            guard (try? checkpoint()) != nil else {
                if self.generation == attempt {
                    self.generation = nil
                    self.activeScope = nil
                    self.activeBinding = nil
                }
                return
            }
            switch outcome {
            case .completed:
                let date = self.now()
                guard (try? checkpoint()) != nil else { return }
                self.ordinal &+= 1
                self.successes[scope] = Success(date: date, ordinal: self.ordinal)
                if self.successes.count > self.capacity,
                   let oldest = self.successes.min(by: { $0.value.ordinal < $1.value.ordinal })?.key
                {
                    self.successes[oldest] = nil
                }
                self.generation = nil
                self.activeScope = nil
                self.activeBinding = nil
                didRefresh(date)
            case let .failed(error):
                self.generation = nil
                self.activeScope = nil
                self.activeBinding = nil
                didFail(error)
            case .cancelled:
                self.generation = nil
                self.activeScope = nil
                self.activeBinding = nil
            }
        })
        return generation == attempt
    }

    /// Retires pending work without discarding successful freshness for other accounts.
    public func cancel() {
        generation = nil
        activeScope = nil
        activeBinding = nil
        requestOwner.cancel()
    }

    isolated deinit { requestOwner.cancel() }
}
