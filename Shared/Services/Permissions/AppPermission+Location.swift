//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

#if os(iOS)
import CoreLocation
import SwiftfinLocalization

extension AppPermission {

    static let location = AppPermission(
        id: "location",
        displayTitle: L10n.location,
        privacyDescriptionKey: "NSLocationWhenInUseUsageDescription",
        canRequest: {
            CLLocationManager().authorizationStatus == .notDetermined
        },
        request: { _ in
            guard CLLocationManager.locationServicesEnabled() else {
                return .denied
            }

            guard CLLocationManager().authorizationStatus == .notDetermined else {
                return Self.locationStatus
            }

            return try await LocationPermissionRequest().request()
        },
        status: {
            Self.locationStatus
        }
    )

    private static var locationStatus: PermissionStatus {
        switch CLLocationManager().authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            .authorized
        case .denied, .restricted:
            .denied
        case .notDetermined:
            .unknown
        @unknown default:
            .unknown
        }
    }
}

@MainActor
private final class LocationPermissionRequest: NSObject, CLLocationManagerDelegate {

    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<PermissionStatus, Error>?

    func request() async throws -> PermissionStatus {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            manager.delegate = self
            manager.requestWhenInUseAuthorization()
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus.rawValue
        Task { @MainActor [weak self] in
            switch CLAuthorizationStatus(rawValue: status) {
            case .authorizedAlways, .authorizedWhenInUse:
                self?.finish(.authorized)
            case .denied, .restricted:
                self?.finish(.denied)
            case .notDetermined:
                break
            default:
                self?.finish(.unknown)
            }
        }
    }

    private func finish(_ status: PermissionStatus) {
        continuation?.resume(returning: status)
        continuation = nil
        manager.delegate = nil
    }
}
#endif
