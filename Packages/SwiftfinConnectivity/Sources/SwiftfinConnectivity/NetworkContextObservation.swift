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

/// One observation lease and one consumer. Cancel when its session stops.
/// Values are immutable; neither native paths nor native monitors escape.
@MainActor
public final class NetworkContextObservation {
    public let values: AsyncStream<NetworkConnectionContext>
    private let continuation: AsyncStream<NetworkConnectionContext>.Continuation
    private let driver: any NetworkPathDriving
    private let lookupSSID: @Sendable () async -> String?
    private var listener: Task<Void, Never>?
    private var enrichment: Task<Void, Never>?
    private var latestSequence: UInt64 = 0
    private var cancelled = false

    public convenience init() {
        self.init(driver: NativeNetworkPathDriver(), lookupSSID: NetworkConnectivity.currentWifiSSID)
    }

    init(driver: any NetworkPathDriving, lookupSSID: @escaping @Sendable () async -> String?) {
        let pair = AsyncStream<NetworkConnectionContext>.makeStream(bufferingPolicy: .bufferingNewest(1))
        values = pair.stream
        continuation = pair.continuation
        self.driver = driver
        self.lookupSSID = lookupSSID
        let snapshots = driver.snapshots
        listener = Task { [weak self] in
            for await snapshot in snapshots {
                guard !Task.isCancelled else { return }
                self?.receive(snapshot)
            }
        }
    }

    private func receive(_ snapshot: NetworkPathSnapshot) {
        guard !cancelled, snapshot.sequence > latestSequence else { return }
        latestSequence = snapshot.sequence
        enrichment?.cancel()
        enrichment = nil
        guard snapshot.isSatisfied, snapshot.interface == .wifi else {
            continuation.yield(.init(isSatisfied: snapshot.isSatisfied, interface: snapshot.interface, wifiSSID: nil))
            return
        }
        let lookupSSID = self.lookupSSID
        enrichment = Task { [weak self] in
            let ssid = await lookupSSID()
            guard !Task.isCancelled, let self, !self.cancelled, self.latestSequence == snapshot.sequence else { return }
            self.continuation.yield(.init(isSatisfied: true, interface: snapshot.interface, wifiSSID: ssid))
            self.enrichment = nil
        }
    }

    public func cancel() {
        guard !cancelled else { return }
        cancelled = true
        listener?.cancel()
        listener = nil
        enrichment?.cancel()
        enrichment = nil
        driver.cancel()
        continuation.finish()
    }

    isolated deinit {
        if !cancelled {
            driver.cancel()
        }
        listener?.cancel()
        enrichment?.cancel()
        continuation.finish()
    }
}
