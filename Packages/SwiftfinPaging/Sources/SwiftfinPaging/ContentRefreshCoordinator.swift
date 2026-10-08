//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation

public struct ContentRefreshOperation: Sendable {
    public typealias Checkpoint = @MainActor @Sendable () throws -> Void
    public let identity: ObjectIdentifier
    public let refresh: @MainActor @Sendable (@escaping Checkpoint) async throws -> Void

    public init(identity: ObjectIdentifier, refresh: @escaping @MainActor @Sendable () async throws -> Void) {
        self.identity = identity
        self.refresh = { validate in
            try validate()
            try await refresh()
            try validate()
        }
    }

    /// Nested schedulers must retain this checkpoint through their own publication.
    public init(identity: ObjectIdentifier, scopedRefresh: @escaping @MainActor @Sendable (@escaping Checkpoint) async throws -> Void) {
        self.identity = identity
        self.refresh = scopedRefresh
    }
}

/// Owns candidate lifetime, refresh workers and successful change-signal receipts.
@MainActor
public final class ContentRefreshCoordinator<Group> {
    private var candidates: [Group] = []
    private var generation = UUID()
    private var signal: UInt64 = 0
    private var completedSignal: UInt64 = 0
    public init() {}
    public var hasPendingChanges: Bool {
        signal != completedSignal
    }

    public func markChanged() {
        signal &+= 1
    }

    public func shouldRefresh(sinceLastDisappear interval: TimeInterval, staleThreshold: TimeInterval = 60) -> Bool {
        interval > staleThreshold || hasPendingChanges
    }

    public func cancel() {
        generation = UUID()
    }

    private func check(_ epoch: UUID, validate: ContentRefreshOperation.Checkpoint) throws {
        try Task.checkCancellation()
        guard generation == epoch else { throw CancellationError() }
        try validate()
        guard generation == epoch else { throw CancellationError() }
    }

    public func refresh(
        inBackground: Bool,
        validate: @escaping ContentRefreshOperation.Checkpoint = {},
        makeGroups: @MainActor @Sendable () async throws -> [Group],
        operations: @MainActor @Sendable ([Group], Bool) -> [ContentRefreshOperation],
        shouldResolve: @MainActor @Sendable (Group) -> Bool
    ) async throws -> [Group] {
        // Rejected queued work must not retire a newer admitted refresh.
        try Task.checkCancellation()
        try validate()
        generation = UUID()
        let epoch = generation, observedSignal = signal
        let checkpoint: ContentRefreshOperation.Checkpoint = { [weak self] in
            guard let self else { throw CancellationError() }
            try self.check(epoch, validate: validate)
        }
        return try await withTaskCancellationHandler {
            do {
                try checkpoint()
                let staged: [Group]
                if inBackground {
                    staged = candidates
                } else {
                    candidates = []
                    staged = try await makeGroups()
                }
                try checkpoint()
                var seen = Set<ObjectIdentifier>()
                let unique = operations(staged, inBackground).filter { seen.insert($0.identity).inserted }
                try checkpoint()
                try await withThrowingTaskGroup(of: Void.self) { group in
                    for operation in unique {
                        group.addTask {
                            try await checkpoint()
                            try await operation.refresh(checkpoint)
                            try await checkpoint()
                        }
                    }
                    try await group.waitForAll()
                }
                try checkpoint()
                let resolved = try staged.filter { candidate in
                    try checkpoint()
                    let include = shouldResolve(candidate)
                    try checkpoint()
                    return include
                }
                try checkpoint()
                candidates = staged
                completedSignal = observedSignal
                return resolved
            } catch {
                try checkpoint()
                generation = UUID()
                throw error
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                if self?.generation == epoch {
                    self?.cancel()
                }
            }
        }
    }
}
