//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

/// An evaluated prompt result. This value does not grant account access; the
/// credential owner must still compare the submitted PIN with its stored value.
public protocol EvaluatedLocalUserAccessPolicy: Sendable {}

public struct PinEvaluatedUserAccessPolicy: EvaluatedLocalUserAccessPolicy {
    public let pin: String
    public let pinHint: String?

    public init(pin: String, pinHint: String?) {
        self.pin = pin
        self.pinHint = pinHint
    }
}

public enum LocalAccessPINPolicy {
    /// Retain the installed rule: 4...30 extended grapheme clusters, without
    /// trimming, numeric-only restrictions or normalization.
    public static func isValid(_ pin: String) -> Bool {
        (4 ... 30).contains(pin.count)
    }
}
