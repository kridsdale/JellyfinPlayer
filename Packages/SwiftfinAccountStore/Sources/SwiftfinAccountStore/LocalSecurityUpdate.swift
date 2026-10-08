//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation
import SwiftfinAccountModels

/// One local security edit bound to its original user and access policy.
/// Native prompts stay in composition; this owner checks the resulting PIN and
/// preserves the store's credential-first, nontransactional mutation order.
@MainActor
public final class LocalSecurityUpdate {
    private let store: LocalAccountStore
    private let userID: String
    private let originalPolicy: LocalUserAccessPolicy
    private let validate: LocalAccountStore.Checkpoint
    private var verifiedPIN: String?
    private var committed = false
    private var busy = false

    init(store: LocalAccountStore, userID: String, validate: @escaping LocalAccountStore.Checkpoint) {
        self.store = store
        self.userID = userID
        self.originalPolicy = store.accessPolicy(userID: userID)
        self.validate = validate
    }

    private func enter() throws {
        guard !busy else { throw CancellationError() }
        busy = true
    }

    private func checkCurrent(policy: LocalUserAccessPolicy) throws {
        try Task.checkCancellation()
        try validate()
        guard !committed, store.accessPolicy(userID: userID) == policy else { throw CancellationError() }
    }

    public func checkBinding() throws {
        try enter()
        defer { busy = false }
        try checkCurrent(policy: originalPolicy)
    }

    public func check(oldPIN: String) throws -> Bool {
        try enter()
        defer { busy = false }
        try checkCurrent(policy: originalPolicy)
        let matches = try store.matchesPIN(oldPIN, userID: userID, allowMissing: true)
        try checkCurrent(policy: originalPolicy)
        verifiedPIN = matches ? oldPIN : nil
        return matches
    }

    public func commit(policy: LocalUserAccessPolicy, pin: String, hint: String) throws {
        try enter()
        defer { busy = false }
        try checkCurrent(policy: originalPolicy)
        if originalPolicy == .requirePin {
            guard let verifiedPIN else { throw AccountStoreError.incorrectPIN }
            let matches = try store.matchesPIN(verifiedPIN, userID: userID, allowMissing: true)
            try checkCurrent(policy: originalPolicy)
            guard matches else { throw AccountStoreError.incorrectPIN }
        }
        try store.writeLocalSecurityCredential(userID: userID, policy: policy, pin: pin)
        try checkCurrent(policy: originalPolicy)
        store.setAccessPolicy(policy, userID: userID)
        try checkCurrent(policy: policy)
        store.setPINHint(hint, userID: userID)
        try checkCurrent(policy: policy)
        committed = true
    }
}

public extension LocalAccountStore {
    func securityUpdate(userID: String, validate: @escaping Checkpoint) throws -> LocalSecurityUpdate {
        try Task.checkCancellation()
        try validate()
        return LocalSecurityUpdate(store: self, userID: userID, validate: validate)
    }
}
