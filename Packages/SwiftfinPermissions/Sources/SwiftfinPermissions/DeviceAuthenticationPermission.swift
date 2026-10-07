//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation
#if canImport(LocalAuthentication) && !os(tvOS)
import LocalAuthentication
#endif

@MainActor
public enum DeviceAuthenticationPermission {
    public static var canRequest: Bool {
        #if canImport(LocalAuthentication) && !os(tvOS)
        NativeAuthenticationDriver().availability.available
        #else
        false
        #endif
    }

    public static var status: PermissionStatus {
        canRequest ? .authorized : .denied
    }

    public static func request(reason: String) async throws -> PermissionStatus {
        try Task.checkCancellation()
        #if canImport(LocalAuthentication) && !os(tvOS)
        return try await PermissionRequests.authenticate(NativeAuthenticationDriver(), reason: reason)
        #else
        throw PermissionRequestError.unsupportedPlatform
        #endif
    }
}

#if canImport(LocalAuthentication) && !os(tvOS)
@MainActor
private final class NativeAuthenticationDriver: AuthenticationPermissionDriver {
    private let context = LAContext()
    var availability: AuthenticationAvailability {
        var error: NSError?
        let value = context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error)
        return .init(available: value, error: error)
    }

    func begin(reason: String, completion: @escaping @Sendable (Result<Void, any Error>) -> Void) {
        context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) { _, error in
            if let error {
                completion(.failure(error))
            } else {
                completion(.success(()))
            }
        }
    }

    func retire() {
        context.invalidate()
    }
}
#endif
