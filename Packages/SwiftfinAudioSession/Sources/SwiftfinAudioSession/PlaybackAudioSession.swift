//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

#if os(iOS) || os(tvOS)
import AVFAudio
#endif
import Foundation
import OSLog
#if os(tvOS)
import KidsDiagnostics
#endif

/// Serializes the process-wide audio session. An old player's release cannot
/// deactivate a newer player's lease, including while activation is suspended.
@MainActor
public final class PlaybackAudioSession {
    #if os(iOS) || os(tvOS)
    public static let shared = PlaybackAudioSession()
    public convenience init() {
        self.init(activate: Self.activate, deactivate: Self.deactivate)
    }
    #endif
    private let activateSession: @Sendable () async throws -> Void
    private let deactivateSession: @Sendable () async throws -> Void
    public init(
        activate: @escaping @Sendable () async throws -> Void,
        deactivate: @escaping @Sendable () async throws -> Void
    ) {
        activateSession = activate
        deactivateSession = deactivate
    }

    // A synchronization point for internal contract tests; it does not alter leases.
    func finishPendingOperations() async throws {
        try await operation?.value
    }

    private var owners = Set<UUID>()
    private var operation: Task<Void, Error>?
    private var active = false
    private let logger = Logger(subsystem: "org.jellyfin.swiftfin", category: "PlaybackAudioSession")

    public func acquire(_ owner: UUID) -> Task<Void, Error> {
        owners.insert(owner)
        let previous = operation
        let task = Task {
            _ = try? await previous?.value
            guard owners.contains(owner) else { throw CancellationError() }
            guard !active else { return }
            try await activateSession()
            active = true
        }
        operation = task
        return task
    }

    public func release(_ owner: UUID, after drain: @escaping @MainActor () async -> Bool = { true }) {
        guard owners.remove(owner) != nil else { return }
        let previous = operation
        operation = Task {
            _ = try? await previous?.value
            #if os(tvOS)
            let trace = KidsPerformance.begin(.playerDrain)
            #endif
            let stopped = await drain()
            #if os(tvOS)
            trace?.finish(stopped ? .success : .failure)
            #endif
            guard stopped else {
                logger.error("Native output did not stop within the bounded wait")
                return
            }
            guard owners.isEmpty, active else { return }
            do {
                try await deactivateSession()
                active = false
            } catch {
                // Keep the known active state; later leases may still use the
                // session. Never deactivate a newer lease in a delayed retry.
                logger.error("Audio session deactivation failed")
            }
        }
    }

    public func wasInterrupted() {
        active = false
    }

    #if os(iOS) || os(tvOS)
    private nonisolated static func activate() async throws {
        #if os(tvOS)
        let trace = KidsPerformance.begin(.audioActivation)
        defer { trace?.finish(Task.isCancelled ? .cancelled : .failure) }
        #endif
        // Category setup and the compatibility API can block. Keep them off the
        // main actor even on systems predating the asynchronous SDK entry point.
        try await Task.detached(priority: .userInitiated) {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
        }.value
        if #available(iOS 27, tvOS 27, *) {
            guard try await AVAudioSession.sharedInstance().activate(options: []) else {
                throw CancellationError()
            }
        } else {
            try await Task.detached(priority: .userInitiated) {
                try AVAudioSession.sharedInstance().setActive(true)
            }.value
        }
        #if os(tvOS)
        trace?.finish()
        #endif
    }

    private nonisolated static func deactivate() async throws {
        #if os(tvOS)
        let trace = KidsPerformance.begin(.audioDeactivation)
        defer { trace?.finish(Task.isCancelled ? .cancelled : .failure) }
        #endif
        if #available(iOS 27, tvOS 27, *) {
            guard try await AVAudioSession.sharedInstance().deactivate(options: [.notifyOthersOnDeactivation]) else {
                throw CancellationError()
            }
        } else {
            try await Task.detached(priority: .userInitiated) {
                try AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
            }.value
        }
        #if os(tvOS)
        trace?.finish()
        #endif
    }
    #endif
}
