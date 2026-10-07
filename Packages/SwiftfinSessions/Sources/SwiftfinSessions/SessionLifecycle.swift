//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation

@MainActor
public protocol SessionResource: AnyObject {
    func prepare() async
    func start()
    func stop()
}

/// Orders the resources belonging to one account session. A stop invalidates
/// pending preparation before tearing resources down in reverse order.
@MainActor
public final class SessionLifecycle {
    private enum Phase { case idle, preparing, prepared, running, stopped }
    private let resources: [any SessionResource]
    private var phase: Phase = .idle
    private var generation: UInt64 = 0

    public init(resources: [any SessionResource]) {
        self.resources = resources
    }

    public func prepare() async {
        guard phase == .idle else { return }
        phase = .preparing
        generation &+= 1
        let attempt = generation
        for resource in resources {
            guard !Task.isCancelled, generation == attempt else { stop()
                return
            }
            await resource.prepare()
            guard !Task.isCancelled, generation == attempt else {
                // A noncooperating prepare may allocate after the earlier stop.
                resource.stop()
                if generation == attempt {
                    stop()
                }
                return
            }
        }
        phase = .prepared
    }

    public func start() {
        guard phase == .prepared else { return }
        guard !Task.isCancelled else { stop()
            return
        }
        phase = .running
        let attempt = generation
        for resource in resources {
            guard phase == .running, generation == attempt else { return }
            resource.start()
        }
    }

    public func stop() {
        guard phase != .stopped else { return }
        generation &+= 1
        phase = .stopped
        for resource in resources.reversed() {
            resource.stop()
        }
    }

    isolated deinit { stop() }
}

public struct AccountSessionIdentity: Equatable, Sendable {
    public let serverID: String
    public let userID: String
    public init(serverID: String, userID: String) {
        self.serverID = serverID
        self.userID = userID
    }
}

@MainActor
public protocol AccountSessionLifecycle: AnyObject {
    var sessionIdentity: AccountSessionIdentity { get }
    func prepare() async
    func start()
    func stop()
}

/// Owns one published account session. Latest requested replacement wins even
/// when an older resource finishes preparation after cancellation/teardown.
@MainActor
public final class ActiveSessionCoordinator<Session: AccountSessionLifecycle> {
    public private(set) var current: Session?
    private var preparing: Session?
    private var generation: UInt64 = 0
    private var publishedIdentity: AccountSessionIdentity?
    private let publish: @MainActor (Session?, Bool) -> Void

    public init(publish: @escaping @MainActor (Session?, Bool) -> Void) {
        self.publish = publish
    }

    public func replace(with replacement: Session?) async {
        try? await replace(with: replacement, validate: {})
    }

    /// Admission checks precede teardown and surround noncooperating preparation/publication.
    public func replace(with replacement: Session?, validate: @MainActor @Sendable () throws -> Void) async throws {
        try Task.checkCancellation()
        try validate()
        if let current, let replacement, current === replacement {
            return
        }
        generation &+= 1
        let attempt = generation
        let oldPreparing = preparing
        let oldCurrent = current
        preparing = nil
        current = nil
        oldPreparing?.stop()
        oldCurrent?.stop()
        do {
            try validate()
            guard generation == attempt else { throw CancellationError() }
            preparing = replacement
            await replacement?.prepare()
            try Task.checkCancellation()
            try validate()
            guard generation == attempt else { throw CancellationError() }
            preparing = nil
            current = replacement
            let identity = replacement?.sessionIdentity
            let changed = publishedIdentity != identity
            publishedIdentity = identity
            publish(replacement, changed)
            try validate()
            guard generation == attempt else { throw CancellationError() }
            replacement?.start()
        } catch {
            // Never stop an instance that a newer request now owns.
            if generation == attempt {
                preparing = nil
                current = nil
                replacement?.stop()
            } else if current !== replacement, preparing !== replacement {
                replacement?.stop()
            }
            throw error
        }
    }

    public func stop() {
        generation &+= 1
        let oldPreparing = preparing
        let oldCurrent = current
        preparing = nil
        current = nil
        oldPreparing?.stop()
        oldCurrent?.stop()
    }

    isolated deinit { stop() }
}
