//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

// SPDX-License-Identifier: MPL-2.0
import Combine
import Foundation

/// Authority for an action belonging to one exact account lifetime. Identity
/// changes permanently retire old leases, even if the same credentials return.
@MainActor
public final class KidsAccountScope {
    private let host: any KidsAccountHost
    private var identity: KidsAccountIdentity?
    private var revision = UUID()
    private var observation: AnyCancellable?

    public init(host: any KidsAccountHost) {
        self.host = host
        self.identity = host.currentIdentity
        observation = host.identityChanges.sink { [weak self] identity in
            // The host port guarantees synchronous main-actor publication.
            MainActor.assumeIsolated {
                guard let self, self.identity != identity else { return }
                self.identity = identity
                self.revision = UUID()
            }
        }
    }

    public func capture() -> Lease {
        let revision = revision
        let published = identity == host.currentIdentity
        return Lease { [weak self] in
            guard let self else { return false }
            return published && self.revision == revision && self.host.currentIdentity == self.identity
        }
    }

    /// The receipt does not retain its owner, host, credentials or subscriptions.
    @MainActor
    public struct Lease: Sendable {
        private let matches: @MainActor @Sendable () -> Bool
        fileprivate init(matches: @escaping @MainActor @Sendable () -> Bool) {
            self.matches = matches
        }

        /// Cancellation does not revoke valid final playback checkpoints.
        public var isCurrent: Bool {
            matches()
        }

        public func check() throws {
            try Task.checkCancellation()
            guard isCurrent else { throw CancellationError() }
        }
    }
}
