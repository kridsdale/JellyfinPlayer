//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation

public struct ContentRefreshOperation: Sendable {
    public let identity: ObjectIdentifier
    public let refresh: @MainActor @Sendable () async throws -> Void
    public init(identity: ObjectIdentifier, refresh: @escaping @MainActor @Sendable () async throws -> Void) {
        self.identity = identity
        self.refresh = refresh
    }
}

/// Refresh candidates and change signals stay on the UI owner actor. Concurrent
/// workers transfer only immutable operation IDs and actor-isolated closures.
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

    public func refresh(
        inBackground: Bool,
        makeGroups: @MainActor @Sendable () async throws -> [Group],
        operations: @MainActor @Sendable ([Group], Bool) -> [ContentRefreshOperation],
        shouldResolve: @MainActor @Sendable (Group) -> Bool
    ) async throws -> [Group] {
        generation = UUID()
        let epoch = generation, observedSignal = signal
        try Task.checkCancellation()
        let staged: [Group]
        if inBackground {
            staged = candidates
        } else {
            candidates = []
            staged = try await makeGroups()
        }
        try check(epoch)
        var seen = Set<ObjectIdentifier>()
        let unique = operations(staged, inBackground).filter { seen.insert($0.identity).inserted }
        try await withThrowingTaskGroup(of: Void.self) { group in
            for operation in unique {
                group.addTask {
                    try Task.checkCancellation()
                    try await operation.refresh()
                    try Task.checkCancellation()
                }
            }
            try await group.waitForAll()
        }
        try check(epoch)
        candidates = staged
        completedSignal = observedSignal
        return staged.filter(shouldResolve)
    }

    private func check(_ epoch: UUID) throws {
        try Task.checkCancellation()
        guard generation == epoch else { throw CancellationError() }
    }
}
