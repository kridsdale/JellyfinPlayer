//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation
import Pulse
import SwiftfinNetworking
import UIKit

extension JellyfinTransport {
    @MainActor
    static func swiftfin(
        url: URL,
        accessToken: String? = nil,
        policy: TransportSessionPolicy = .standard,
        logging: Bool = true
    ) -> JellyfinTransport {
        let identity = TransportClientIdentity(
            platform: UIDevice.platform,
            deviceName: UIDevice.current.name,
            vendorID: UIDevice.vendorUUIDString,
            version: (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "0.0.1"
        )
        return JellyfinTransport(
            url: url, accessToken: accessToken, identity: identity, policy: policy,
            sessionDelegate: logging ? URLSessionProxyDelegate(logger: NetworkLogger.swiftfin()) : nil
        )
    }
}
