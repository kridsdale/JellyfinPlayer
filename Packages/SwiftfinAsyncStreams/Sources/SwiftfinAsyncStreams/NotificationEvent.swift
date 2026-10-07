//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Combine
import Foundation

/// Immutable notification description. Raw delivery remains synchronous on the
/// posting executor; callers choose UI scheduling at their composition boundary.
public struct NotificationEvent<Payload: Sendable>: Sendable {
    public let name: Notification.Name
    private let decode: @Sendable ([AnyHashable: Any]) -> Payload?

    public init(_ name: Notification.Name, decode: (@Sendable ([AnyHashable: Any]) -> Payload?)? = nil) {
        self.name = name
        self.decode = decode ?? { $0["payload"] as? Payload }
    }

    public func post(_ payload: Payload, to center: NotificationCenter) {
        center.post(name: name, object: nil, userInfo: ["payload": payload])
    }

    public func post(to center: NotificationCenter) where Payload == Void {
        center.post(name: name, object: nil, userInfo: nil)
    }

    public func publisher(in center: NotificationCenter) -> AnyPublisher<Payload, Never> {
        center.publisher(for: name).compactMap { [decode] notification in
            if Payload.self == Void.self {
                return () as? Payload
            }
            guard let userInfo = notification.userInfo else { return nil }
            return decode(userInfo)
        }.eraseToAnyPublisher()
    }

    /// Signal-only delivery for actor-isolated platform status readers. No raw
    /// Notification/userInfo value crosses the owned main-actor bridge.
    @MainActor
    public func mainActorPublisher(
        in center: NotificationCenter,
        read: @escaping @MainActor @Sendable () -> Payload?
    ) -> AnyPublisher<Payload, Never> {
        notificationSignals(for: name, in: center)
            .receive(on: DispatchQueue.main)
            .compactMap { [read] _ in MainActor.assumeIsolated { read() } }
            .eraseToAnyPublisher()
    }
}

// Native callbacks can arrive on any executor. Build this value-free projection
// outside actor isolation so the closure cannot inherit a main-actor assertion.
private func notificationSignals(for name: Notification.Name, in center: NotificationCenter) -> AnyPublisher<Void, Never> {
    center.publisher(for: name).map { _ in () }.eraseToAnyPublisher()
}
