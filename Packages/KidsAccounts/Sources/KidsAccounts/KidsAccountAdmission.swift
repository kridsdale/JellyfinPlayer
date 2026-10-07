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
import KidsDomain
import SwiftfinAsyncStreams

/// Owns admission relevance across catalog validation, credential storage and activation.
/// It starts no tasks and never undoes effects that already passed their checkpoint.
@MainActor
public final class KidsAccountAdmission {
    private let host: any KidsAccountHost
    private let requests = AsyncOperationGate()
    private var attempt: Attempt?
    private var observation: AnyCancellable?

    public init(host: any KidsAccountHost) {
        self.host = host
        observation = host.identityChanges.sink { [weak self] identity in
            // The account port guarantees synchronous main-actor delivery.
            MainActor.assumeIsolated { self?.attempt?.receive(identity) }
        }
    }

    public func begin() throws -> Attempt {
        try Task.checkCancellation()
        let next = Attempt(host: host, validate: requests.begin())
        attempt = next
        return next
    }

    public func cancel() {
        attempt = nil
        requests.cancel()
    }

    @MainActor
    public final class Attempt {
        private weak var host: (any KidsAccountHost)?
        private let initialIdentity: KidsAccountIdentity?
        private let validateGeneration: KidsAccountCheckpoint
        private var target: KidsAccountIdentity?
        private var targetAssigned = false
        private var published = false
        private var relevant = true

        fileprivate init(host: any KidsAccountHost, validate: @escaping KidsAccountCheckpoint) {
            self.host = host
            initialIdentity = host.currentIdentity
            validateGeneration = validate
        }

        public var checkpoint: KidsAccountCheckpoint {
            { [weak self] in
                guard let self else { throw CancellationError() }
                try check()
            }
        }

        public func check() throws {
            try validateGeneration()
            guard relevant, let host, permits(host.currentIdentity) else { throw CancellationError() }
        }

        private func permits(_ identity: KidsAccountIdentity?) -> Bool {
            if published {
                return identity == target
            }
            return identity == initialIdentity || (targetAssigned && identity == target)
        }

        fileprivate func receive(_ identity: KidsAccountIdentity?) {
            if !permits(identity) {
                relevant = false
            }
            if let target, identity == target {
                published = true
            }
        }

        public func prepare(_ account: KidsAuthenticatedAccount, binding: KidsBinding) throws {
            try check()
            guard account.identity.matches(binding), !targetAssigned || target == account.identity else { throw KidsContractError.denied }
            // Saving replacement credentials can change the current identity synchronously.
            target = account.identity
            targetAssigned = true
            try account.prepareActivation(binding: binding, validate: checkpoint)
        }

        public func activate(_ account: KidsAuthenticatedAccount, binding: KidsBinding) async throws {
            try check()
            guard targetAssigned, target == account.identity else { throw KidsContractError.denied }
            try await account.activate(binding: binding, validate: checkpoint)
            try check()
            guard host?.currentIdentity == account.identity else { throw KidsContractError.denied }
        }

        public func signOut() async throws {
            try check()
            guard let host else { throw CancellationError() }
            target = nil
            targetAssigned = true
            published = false
            try await host.signOut(validate: checkpoint)
            try check()
            guard host.currentIdentity == nil else { throw KidsContractError.denied }
        }
    }
}
