//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

// Swiftfin is subject to the Mozilla Public License, v2.0.
import Foundation
import Network
import os
import SwiftfinAccountModels

/// Sequence is assigned at native callback receipt, before any executor hop.
struct NetworkPathSnapshot: Sendable {
    let sequence: UInt64
    let isSatisfied: Bool
    let interface: ServerConnection.Interface
}

@MainActor
protocol NetworkPathDriving: AnyObject {
    var snapshots: AsyncStream<NetworkPathSnapshot> { get }
    func cancel()
}

/// SDK path objects remain in this adapter. Its callback transfers only values.
@MainActor
final class NativeNetworkPathDriver: NetworkPathDriving {
    let snapshots: AsyncStream<NetworkPathSnapshot>
    private let continuation: AsyncStream<NetworkPathSnapshot>.Continuation
    private let monitor: NWPathMonitor
    private let receipt = OSAllocatedUnfairLock(initialState: ReceiptState())

    private struct ReceiptState: Sendable {
        var sequence: UInt64 = 0
        var cancelled = false
    }

    init() {
        let pair = AsyncStream<NetworkPathSnapshot>.makeStream(bufferingPolicy: .bufferingNewest(1))
        snapshots = pair.stream
        continuation = pair.continuation
        monitor = NWPathMonitor()
        let receipt = self.receipt
        let continuation = self.continuation
        monitor.pathUpdateHandler = { path in
            let value = receipt.withLock { state -> NetworkPathSnapshot? in
                guard !state.cancelled else { return nil }
                state.sequence += 1
                let interface: ServerConnection.Interface = if path.usesInterfaceType(.wifi) {
                    .wifi
                } else if path.usesInterfaceType(.cellular) {
                    .cellular
                } else {
                    .any
                }
                return .init(sequence: state.sequence, isSatisfied: path.status == .satisfied, interface: interface)
            }
            if let value {
                continuation.yield(value)
            }
        }
        monitor.start(queue: DispatchQueue(label: "Swiftfin.NetworkConnectivity"))
    }

    func cancel() {
        receipt.withLock { $0.cancelled = true }
        monitor.cancel()
        continuation.finish()
    }

    isolated deinit {
        receipt.withLock { $0.cancelled = true }
        monitor.cancel()
        continuation.finish()
    }
}
