//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation
import SwiftfinAsyncStreams

/// Orders account choices before caller-owned authentication or UI scheduling.
/// Passive restoration cannot displace an unfinished explicit choice. Native
/// policy evaluation, persisted selection and routing are supplied by the host.
@MainActor
public final class SessionSelectionCoordinator<Session: AccountSessionLifecycle> {
    public typealias Checkpoint = AsyncOperationGate.Checkpoint
    public enum Priority: Sendable { case explicit, restoration }
    public struct Request: Sendable {
        fileprivate let id: UUID
        fileprivate let ownerID: UUID
        public let check: Checkpoint

        /// Add a resolved account binding without submitting a new choice.
        public func validating(_ validate: @escaping Checkpoint) -> Self {
            Self(id: id, ownerID: ownerID, check: {
                try check()
                try validate()
                try check()
            })
        }
    }

    private let sessions: ActiveSessionCoordinator<Session>
    private let ownerID = UUID()
    private var generation: UUID?
    private var pendingPriority: Priority?
    private var executing = false

    public init(sessions: ActiveSessionCoordinator<Session>) {
        self.sessions = sessions
    }

    /// A failed/reentrant preflight leaves newer intent untouched. Capture the
    /// request synchronously at submission, before starting a native prompt/task.
    public func begin(priority: Priority, validate: @escaping Checkpoint = {}) throws -> Request? {
        let previous = generation
        try Task.checkCancellation()
        try validate()
        guard previous == generation else { throw CancellationError() }
        if priority == .restoration, pendingPriority == .explicit {
            return nil
        }
        let id = UUID()
        generation = id
        pendingPriority = priority
        executing = false
        return Request(id: id, ownerID: ownerID, check: { [weak self] in
            try Task.checkCancellation()
            guard let self, generation == id else { throw CancellationError() }
            try validate()
            guard generation == id else { throw CancellationError() }
        })
    }

    /// Abandon a queued authentication handoff. A host disappearing during
    /// publication cannot revoke the activation that is replacing that host UI.
    public func cancelPending(_ request: Request) {
        guard request.ownerID == ownerID, generation == request.id, !executing, pendingPriority != nil else { return }
        generation = nil
        pendingPriority = nil
    }

    /// Authentication completes before teardown. Every host effect and resource
    /// publication borrows the same intent checkpoint. Accepted effects are not
    /// rolled back; replaced operations cannot proceed to their next effect.
    public func activate(
        _ request: Request,
        with session: Session?,
        prepare: @MainActor (Checkpoint) async throws -> Void = { _ in },
        willSelect: @MainActor (Checkpoint) throws -> Void = { _ in },
        didSelect: @MainActor (Checkpoint) throws -> Void = { _ in }
    ) async throws {
        guard request.ownerID == ownerID, generation == request.id, !executing, pendingPriority != nil
        else { throw CancellationError() }
        executing = true
        defer {
            if generation == request.id {
                executing = false
                pendingPriority = nil
            }
        }
        do {
            try request.check()
            try await prepare(request.check)
            try request.check()
            try willSelect(request.check)
            try request.check()
            try await sessions.replace(with: session, validate: request.check)
            try request.check()
            try didSelect(request.check)
            try request.check()
        } catch {
            // A late native/transport error belongs to the retired intent too.
            try request.check()
            throw error
        }
    }
}
