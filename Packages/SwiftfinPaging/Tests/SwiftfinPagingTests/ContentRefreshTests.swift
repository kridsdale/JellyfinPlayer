//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation
import SwiftfinPaging
import Testing

private enum RefreshFailure: Error { case offline }
@MainActor
private final class RefreshOwner { var full = 0
    var background = 0
    var resolved = true
}

@MainActor
private final class RefreshGate {
    var continuation: CheckedContinuation<Void, Never>?
    func wait() async {
        await withCheckedContinuation { continuation = $0 }
    }

    func finish() {
        continuation?.resume()
        continuation = nil
    }
}

@MainActor
private func settle(_ condition: () -> Bool) async {
    for _ in 0 ..< 2000 {
        if condition() {
            return
        }
        await Task.yield()
    }
    #expect(condition())
}

@MainActor
private func operations(_ groups: [RefreshOwner], _ background: Bool) -> [ContentRefreshOperation] {
    groups.map { owner in .init(identity: ObjectIdentifier(owner)) {
        if background {
            owner.background += 1
        } else {
            owner.full += 1
        }
    } }
}

@Suite("Content group refresh ownership")
@MainActor
struct ContentRefreshTests {
    @Test
    func `full and background refresh deduplicate owners and resolve after refresh`() async throws {
        let coordinator = ContentRefreshCoordinator<RefreshOwner>()
        let a = RefreshOwner(), b = RefreshOwner()
        b.resolved = false
        let groups = try await coordinator.refresh(
            inBackground: false,
            makeGroups: { [a, a, b] },
            operations: operations,
            shouldResolve: { $0.resolved }
        )
        #expect(groups.count == 2 && groups[0] === a && a.full == 1 && b.full == 1)
        let background = try await coordinator.refresh(
            inBackground: true,
            makeGroups: { throw RefreshFailure.offline },
            operations: operations,
            shouldResolve: { $0.resolved }
        )
        #expect(background.count == 2 && a.background == 1 && b.background == 1)
    }

    @Test
    func `stale threshold is strict and signals are consumed only on success`() async throws {
        let c = ContentRefreshCoordinator<RefreshOwner>()
        #expect(!c.shouldRefresh(sinceLastDisappear: 60) && c.shouldRefresh(sinceLastDisappear: 61))
        c.markChanged()
        #expect(c.hasPendingChanges && c.shouldRefresh(sinceLastDisappear: 0))
        await #expect(throws: RefreshFailure.self) { try await c.refresh(
            inBackground: false,
            makeGroups: { throw RefreshFailure.offline },
            operations: operations,
            shouldResolve: { $0.resolved }
        ) }
        #expect(c.hasPendingChanges)
        _ = try await c.refresh(inBackground: false, makeGroups: { [] }, operations: operations, shouldResolve: { $0.resolved })
        #expect(!c.hasPendingChanges)
    }

    @Test
    func `changes during await remain pending for next refresh`() async throws {
        let c = ContentRefreshCoordinator<RefreshOwner>()
        let gate = RefreshGate()
        c.markChanged()
        let task = Task { try await c.refresh(inBackground: false, makeGroups: { await gate.wait()
            return []
        }, operations: operations, shouldResolve: { $0.resolved }) }
        await settle { gate.continuation != nil }
        c.markChanged()
        gate.finish()
        _ = try await task.value
        #expect(c.hasPendingChanges)
        _ = try await c.refresh(inBackground: true, makeGroups: { [] }, operations: operations, shouldResolve: { $0.resolved })
        #expect(!c.hasPendingChanges)
    }

    @Test
    func `newer refresh rejects late old candidates`() async throws {
        let c = ContentRefreshCoordinator<RefreshOwner>()
        let gate = RefreshGate()
        let old = RefreshOwner(), fresh = RefreshOwner()
        let task = Task { try await c.refresh(inBackground: false, makeGroups: { await gate.wait()
            return [old]
        }, operations: operations, shouldResolve: { $0.resolved }) }
        await settle { gate.continuation != nil }
        let result = try await c.refresh(
            inBackground: false,
            makeGroups: { [fresh] },
            operations: operations,
            shouldResolve: { $0.resolved }
        )
        gate.finish()
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(result.first === fresh && old.full == 0 && fresh.full == 1)
        let later = try await c.refresh(inBackground: true, makeGroups: { [] }, operations: operations, shouldResolve: { $0.resolved })
        #expect(later.first === fresh && fresh.background == 1 && old.background == 0)
    }

    @Test
    func `cancelled worker cannot clear pending signal`() async throws {
        let c = ContentRefreshCoordinator<RefreshOwner>()
        c.markChanged()
        let gate = RefreshGate()
        let owner = RefreshOwner()
        let task = Task { try await c.refresh(
            inBackground: false,
            makeGroups: { [owner] },
            operations: { groups, _ in groups.map { owner in .init(identity: ObjectIdentifier(owner)) { await gate.wait() } } },
            shouldResolve: { $0.resolved }
        ) }
        await settle { gate.continuation != nil }
        task.cancel()
        gate.finish()
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(c.hasPendingChanges)
    }

    @Test
    func `explicit invalidation rejects completed old read`() async throws {
        let c = ContentRefreshCoordinator<RefreshOwner>()
        let gate = RefreshGate()
        let task = Task { try await c.refresh(inBackground: false, makeGroups: { await gate.wait()
            return []
        }, operations: operations, shouldResolve: { $0.resolved }) }
        await settle { gate.continuation != nil }
        c.cancel()
        gate.finish()
        await #expect(throws: CancellationError.self) { try await task.value }
    }

    @Test
    func `rejected queued caller cannot retire current candidates`() async throws {
        let c = ContentRefreshCoordinator<RefreshOwner>()
        let gate = RefreshGate(), owner = RefreshOwner()
        let current = Task { try await c.refresh(inBackground: false, makeGroups: { await gate.wait()
            return [owner]
        }, operations: operations, shouldResolve: { $0.resolved }) }
        await settle { gate.continuation != nil }
        await #expect(throws: CancellationError.self) {
            try await c.refresh(
                inBackground: false,
                validate: { throw CancellationError() },
                makeGroups: { Issue.record("Rejected caller read groups")
                    return []
                },
                operations: operations,
                shouldResolve: { $0.resolved }
            )
        }
        gate.finish()
        let result = try await current.value
        #expect(result.first === owner && owner.full == 1)
    }

    @Test
    func `retired caller converts delayed ordinary read failure to cancellation`() async {
        let c = ContentRefreshCoordinator<RefreshOwner>()
        let gate = RefreshGate(), flag = RefreshScopeFlag()
        c.markChanged()
        let task = Task { try await c.refresh(inBackground: false, validate: { try flag.check() }, makeGroups: { await gate.wait()
            throw RefreshFailure.offline
        }, operations: operations, shouldResolve: { $0.resolved }) }
        await settle { gate.continuation != nil }
        flag.current = false
        gate.finish()
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(c.hasPendingChanges)
    }

    @Test
    func `operation builder reentry retires workers before reads`() async {
        let c = ContentRefreshCoordinator<RefreshOwner>(), owner = RefreshOwner()
        c.markChanged()
        await #expect(throws: CancellationError.self) { try await c.refresh(
            inBackground: false,
            makeGroups: { [owner] },
            operations: { groups, background in
                c.cancel()
                return operations(groups, background)
            },
            shouldResolve: { $0.resolved }
        ) }
        #expect(owner.full == 0 && c.hasPendingChanges)
    }

    @Test
    func `resolution reentry cannot consume change signal or commit candidates`() async {
        let c = ContentRefreshCoordinator<RefreshOwner>(), owner = RefreshOwner()
        c.markChanged()
        await #expect(throws: CancellationError.self) { try await c.refresh(
            inBackground: false,
            makeGroups: { [owner] },
            operations: operations,
            shouldResolve: { _ in c.cancel()
                return true
            }
        ) }
        #expect(c.hasPendingChanges && owner.full == 1)
        let background = try? await c.refresh(
            inBackground: true,
            makeGroups: { [] },
            operations: operations,
            shouldResolve: { $0.resolved }
        )
        #expect(background?.isEmpty == true && owner.background == 0)
    }

    @Test
    func `nested independently scheduled page rejects retired parent before publication`() async {
        let c = ContentRefreshCoordinator<RefreshOwner>(), owner = RefreshOwner()
        let gate = RefreshGate(), flag = RefreshScopeFlag()
        var nested: Task<Void, any Error>?
        let task = Task { try await c.refresh(
            inBackground: false,
            validate: { try flag.check() },
            makeGroups: { [owner] },
            operations: { groups, _ in groups.map { owner in
                ContentRefreshOperation(identity: ObjectIdentifier(owner), scopedRefresh: { validate in
                    let worker = Task { @MainActor in
                        await gate.wait()
                        try validate()
                        owner.full += 1
                    }
                    nested = worker
                    try await worker.value
                })
            } },
            shouldResolve: { $0.resolved }
        ) }
        await settle { gate.continuation != nil }
        flag.current = false
        gate.finish()
        await #expect(throws: CancellationError.self) { try await task.value }
        await #expect(throws: CancellationError.self) { try await nested?.value }
        #expect(owner.full == 0)
    }

    @Test
    func `completed refresh scope permits pagination until newer parent admission`() async throws {
        let c = ContentRefreshCoordinator<RefreshOwner>(), owner = RefreshOwner()
        var checkpoint: ContentRefreshOperation.Checkpoint?
        _ = try await c.refresh(inBackground: false, makeGroups: { [owner] }, operations: { groups, _ in groups.map { owner in
            ContentRefreshOperation(identity: ObjectIdentifier(owner), scopedRefresh: { validate in checkpoint = validate
                try validate()
                owner.full += 1
            })
        } }, shouldResolve: { $0.resolved })
        try checkpoint?()
        _ = try await c.refresh(inBackground: false, makeGroups: { [] }, operations: operations, shouldResolve: { $0.resolved })
        #expect(throws: CancellationError.self) { try checkpoint?() }
    }

    @Test
    func `ordinary worker failure retires accepted child checkpoint and preserves pending signal`() async {
        let c = ContentRefreshCoordinator<RefreshOwner>(), owner = RefreshOwner()
        var checkpoint: ContentRefreshOperation.Checkpoint?
        c.markChanged()
        await #expect(throws: RefreshFailure.self) { try await c.refresh(
            inBackground: false,
            makeGroups: { [owner] },
            operations: { groups, _ in groups.map { owner in
                ContentRefreshOperation(identity: ObjectIdentifier(owner), scopedRefresh: { validate in checkpoint = validate
                    throw RefreshFailure.offline
                })
            } },
            shouldResolve: { $0.resolved }
        ) }
        #expect(c.hasPendingChanges)
        #expect(throws: CancellationError.self) { try checkpoint?() }
    }

    @Test
    func `cancelled queued task cannot retire accepted refresh`() async throws {
        let c = ContentRefreshCoordinator<RefreshOwner>(), owner = RefreshOwner()
        let gate = RefreshGate(), queuedGate = RefreshGate()
        let accepted = Task { try await c.refresh(inBackground: false, makeGroups: { await gate.wait()
            return [owner]
        }, operations: operations, shouldResolve: { $0.resolved }) }
        await settle { gate.continuation != nil }
        let queued = Task { await queuedGate.wait()
            return try await c.refresh(inBackground: false, makeGroups: { [] }, operations: operations, shouldResolve: { $0.resolved })
        }
        await settle { queuedGate.continuation != nil }
        queued.cancel()
        queuedGate.finish()
        await #expect(throws: CancellationError.self) { try await queued.value }
        gate.finish()
        let result = try await accepted.value
        #expect(result.first === owner)
    }
}

@MainActor
private final class RefreshScopeFlag {
    var current = true
    func check() throws {
        if !current {
            throw CancellationError()
        }
    }
}
