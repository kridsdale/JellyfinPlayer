//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation
import os
#if os(iOS) || os(macOS)
import CoreLocation
#endif

@MainActor
public enum LocationPermission {
    public static var canRequest: Bool {
        #if os(iOS) || os(macOS)
        NativeLocationDriver().authorization == .notDetermined
        #else
        false
        #endif
    }

    public static var status: PermissionStatus {
        #if os(iOS) || os(macOS)
        NativeLocationDriver().authorization.status
        #else
        .unknown
        #endif
    }

    public static func request() async throws -> PermissionStatus {
        try Task.checkCancellation()
        #if os(iOS) || os(macOS)
        return try await PermissionRequests.location(NativeLocationDriver())
        #else
        throw PermissionRequestError.unsupportedPlatform
        #endif
    }
}

#if os(iOS) || os(macOS)
private final class LocationCallbacks: Sendable {
    private let callback = OSAllocatedUnfairLock<(@Sendable (PermissionStatus?) -> Void)?>(initialState: nil)
    func install(_ action: @escaping @Sendable (PermissionStatus?) -> Void) {
        callback.withLock { $0 = action }
    }

    func clear() {
        callback.withLock { $0 = nil }
    }

    func send(_ status: PermissionStatus?) {
        let action = callback.withLock { $0 }
        action?(status)
    }
}

@MainActor
private final class NativeLocationDriver: NSObject, CLLocationManagerDelegate, LocationPermissionDriver {
    private let manager = CLLocationManager()
    private nonisolated let callbacks = LocationCallbacks()
    var servicesEnabled: Bool {
        CLLocationManager.locationServicesEnabled()
    }

    var authorization: LocationAuthorization {
        Self.project(manager.authorizationStatus)
    }

    func begin(completion: @escaping @Sendable (PermissionStatus?) -> Void) {
        callbacks.install(completion)
        manager.delegate = self
        manager.requestWhenInUseAuthorization()
    }

    func retire() {
        callbacks.clear()
        manager.delegate = nil
    }

    isolated deinit { callbacks.clear()
        manager.delegate = nil
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = Self.project(manager.authorizationStatus)
        callbacks.send(status == .notDetermined ? nil : status.status)
    }

    private nonisolated static func project(_ status: CLAuthorizationStatus) -> LocationAuthorization {
        switch status {
        case .authorizedAlways: .always
        case .authorizedWhenInUse: .whenInUse
        case .denied: .denied
        case .restricted: .restricted
        case .notDetermined: .notDetermined
        @unknown default: .unknown
        }
    }
}
#endif
