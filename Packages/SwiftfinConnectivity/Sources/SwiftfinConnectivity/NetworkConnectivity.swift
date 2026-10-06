//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

// Swiftfin is subject to the Mozilla Public License, v2.0.
import Foundation
import SwiftfinAccountModels
#if os(iOS)
import NetworkExtension
#endif

public enum NetworkConnectivity {
    /// Returns unavailable on task cancellation and always stops native monitoring.
    @MainActor
    public static func current() async -> NetworkConnectionContext {
        await current(observation: NetworkContextObservation())
    }

    @MainActor
    static func current(observation: NetworkContextObservation) async -> NetworkConnectionContext {
        defer { observation.cancel() }
        var iterator = observation.values.makeAsyncIterator()
        return await iterator.next() ?? .unavailable
    }

    public static func currentWifiSSID() async -> String? {
        #if os(iOS)
        let ssid = await NEHotspotNetwork.fetchCurrent()?.ssid
        return NetworkConnectionContext(isSatisfied: true, interface: .wifi, wifiSSID: ssid).wifiSSID
        #else
        return nil
        #endif
    }
}
