//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation
import JellyfinAPI

/// Owns one account's submitted configuration updates. Accepted writes drain in order;
/// queued replacements coalesce and obsolete work never reports a UI failure.
/// Optimistic presentation belongs to the caller and is not rolled back here.
@MainActor
public final class UserConfigurationUpdates {
    public typealias Checkpoint = @MainActor @Sendable () throws -> Void
    public typealias Failure = @MainActor @Sendable (any Error) -> Void

    private let client: UserAdministrationClient
    private let userID: String
    private var generation: UUID?
    private var tail: Task<Void, Never>?

    init(client: UserAdministrationClient, userID: String, after previous: UserConfigurationUpdates?) {
        self.client = client
        self.userID = userID
        self.tail = previous?.tail
    }

    /// Capture a fresh configuration and caller checkpoint when the button is pressed.
    /// The synchronous callback admits only the current intent before any scheduling.
    @discardableResult
    public func toggle(
        from configuration: UserConfiguration,
        validate: @escaping Checkpoint = {},
        willSubmit: @MainActor @Sendable (UserConfiguration) -> Void = { _ in },
        failure: @escaping Failure = { _ in }
    ) throws -> Bool {
        var updated = configuration
        let enabled = configuration.enableNextEpisodeAutoPlay != true
        updated.enableNextEpisodeAutoPlay = enabled
        try submit(updated, validate: validate, willSubmit: willSubmit, failure: failure)
        return enabled
    }

    /// Submit a complete fresh snapshot. All callers for an account should share
    /// this writer so an admitted older write cannot overtake a newer intent.
    public func submit(
        _ updated: UserConfiguration,
        validate: @escaping Checkpoint = {},
        willSubmit: @MainActor @Sendable (UserConfiguration) -> Void = { _ in },
        failure: @escaping Failure = { _ in },
        completion: @escaping @MainActor @Sendable () -> Void = {}
    ) throws {
        try client.checkBinding()
        try validate()
        let ticket = UUID()
        let previous = tail
        generation = ticket
        willSubmit(updated)
        do {
            try client.checkBinding()
            try validate()
            guard generation == ticket else { throw CancellationError() }
        } catch {
            if generation == ticket {
                generation = nil
            }
            throw error
        }

        let client = client
        let userID = userID
        tail = Task { [weak self] in
            // Cancellation must not bypass a sender that is still accepting an
            // earlier write. Keep its handle until it actually finishes.
            await previous?.value
            guard self?.accepts(ticket, validate: validate) == true else { return }
            do {
                try await client.updateConfiguration(id: userID, configuration: updated)
                guard let self, accepts(ticket, validate: validate) else { return }
                generation = nil
                tail = nil
                completion()
            } catch {
                guard let self, accepts(ticket, validate: validate) else { return }
                generation = nil
                tail = nil
                guard !(error is CancellationError), (error as? URLError)?.code != .cancelled else { return }
                failure(error)
            }
        }
    }

    private func accepts(_ ticket: UUID, validate: Checkpoint) -> Bool {
        guard generation == ticket else { return false }
        do {
            try client.checkBinding()
            try validate()
            return generation == ticket
        } catch { return false }
    }

    public func cancel() {
        generation = nil
        // Retain the tail so later submission cannot overtake an accepted write.
        tail?.cancel()
    }

    /// Waits for the tail owned at entry; does not submit or retry a command.
    public func waitUntilFinished() async {
        let pending = tail
        await pending?.value
    }

    isolated deinit { tail?.cancel() }
}
