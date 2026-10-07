//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

// SPDX-License-Identifier: MPL-2.0
import Foundation
import KidsDomain

/// A storage failure cannot authorize first-time setup or replace an existing PIN.
public enum KidsParentPINError: Error, Equatable, Sendable, LocalizedError {
    case unavailable

    public var errorDescription: String? {
        "Parent PIN storage is temporarily unavailable. Try again."
    }
}

@MainActor
public extension KidsAccountHost {
    /// Presentation hint only. Unreadable storage keeps the existing-PIN route.
    /// Actions must read again through the throwing authorization methods.
    var hasParentPIN: Bool {
        do { return try parentPIN != nil }
        catch { return true }
    }

    /// Recovery still requires the caller to verify the previous account and libraries.
    /// It never bypasses an unavailable credential store.
    func authorizeParentSetup(unlocked: Bool, recovering: Bool = false) throws {
        let existing = try parentPINForAuthorization()
        guard existing == nil || unlocked || recovering else { throw KidsContractError.denied }
    }

    func matchesParentPIN(_ pin: String) throws -> Bool {
        guard let existing = try parentPINForAuthorization() else { return false }
        return existing == pin
    }

    /// Credential storage succeeds before the caller may grant parent access.
    func replaceParentPIN(_ pin: String, unlocked: Bool) throws {
        try authorizeParentSetup(unlocked: unlocked)
        guard (4 ... 8).contains(pin.count), pin.allSatisfy(\.isNumber) else { throw KidsContractError.denied }
        do { try storeParentPIN(pin) }
        catch { throw KidsParentPINError.unavailable }
    }

    private func parentPINForAuthorization() throws -> String? {
        do { return try parentPIN }
        catch { throw KidsParentPINError.unavailable }
    }
}
