//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation

struct AuthenticationAvailability: Sendable {
    let available: Bool
    let error: (any Error)?
}

@MainActor
protocol AuthenticationPermissionDriver: AnyObject {
    var availability: AuthenticationAvailability { get }
    func begin(reason: String, completion: @escaping @Sendable (Result<Void, any Error>) -> Void)
    func retire()
}

@MainActor
protocol LocationPermissionDriver: AnyObject {
    var servicesEnabled: Bool { get }
    var authorization: LocationAuthorization { get }
    func begin(completion: @escaping @Sendable (PermissionStatus?) -> Void)
    func retire()
}

enum LocationAuthorization: Sendable {
    case always
    case whenInUse
    case denied
    case restricted
    case notDetermined
    case unknown
    var status: PermissionStatus {
        switch self {
        case .always, .whenInUse: .authorized
        case .denied, .restricted: .denied
        case .notDetermined, .unknown: .unknown
        }
    }
}

@MainActor
enum PermissionRequests {
    static func authenticate(_ driver: any AuthenticationPermissionDriver, reason: String) async throws -> PermissionStatus {
        try Task.checkCancellation()
        let availability = driver.availability
        try Task.checkCancellation()
        guard availability.available else {
            if let error = availability.error {
                throw error
            }
            throw PermissionRequestError.deviceAuthenticationUnavailable
        }
        let reply = PermissionReply()
        defer { driver.retire() }
        let value = try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                guard reply.install(continuation) else { return }
                if Task.isCancelled {
                    reply.cancel()
                    return
                }
                driver.begin(reason: reason) { result in
                    reply.finish(result.map { .authorized })
                }
            }
        } onCancel: { reply.cancel() }
        try Task.checkCancellation()
        return value
    }

    static func location(_ driver: any LocationPermissionDriver) async throws -> PermissionStatus {
        try Task.checkCancellation()
        let servicesEnabled = driver.servicesEnabled
        try Task.checkCancellation()
        guard servicesEnabled else { return .denied }
        let authorization = driver.authorization
        try Task.checkCancellation()
        guard authorization == .notDetermined else { return authorization.status }
        let reply = PermissionReply()
        defer { driver.retire() }
        let value = try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                guard reply.install(continuation) else { return }
                if Task.isCancelled {
                    reply.cancel()
                    return
                }
                driver.begin { status in
                    if let status {
                        reply.finish(.success(status))
                    }
                }
            }
        } onCancel: { reply.cancel() }
        try Task.checkCancellation()
        return value
    }
}
