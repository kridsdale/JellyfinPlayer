//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation

/// An immutable observed network value. Native monitoring and Wi-Fi access
/// belong to the connectivity adapter, not this account/connection model.
public struct NetworkConnectionContext: Equatable, Sendable {
    public let isSatisfied: Bool
    public let interface: ServerConnection.Interface
    public let wifiSSID: String?
    public init(isSatisfied: Bool, interface: ServerConnection.Interface, wifiSSID: String?) {
        self.isSatisfied = isSatisfied
        self.interface = interface
        self.wifiSSID = wifiSSID.flatMap { let trimmed = $0.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
    }

    public static var unavailable: Self {
        .init(isSatisfied: false, interface: .any, wifiSSID: nil)
    }
}
