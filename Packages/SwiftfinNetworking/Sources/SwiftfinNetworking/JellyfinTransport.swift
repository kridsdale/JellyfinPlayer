//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation
import Get
import JellyfinAPI

public struct TransportClientIdentity: Equatable, Sendable {
    public let client: String
    public let deviceName: String
    public let deviceID: String
    public let version: String

    public init(platform: String, deviceName: String, vendorID: String, version: String, locale: Locale = .current) {
        client = "Swiftfin " + platform
        self.deviceName = deviceName.folding(options: .diacriticInsensitive, locale: locale)
            .unicodeScalars.filter { CharacterSet.urlQueryAllowed.contains($0) }.description
        deviceID = platform + "_" + vendorID
        self.version = version
    }
}

public enum TransportSessionPolicy: Sendable {
    case standard
    case connectionProbe
    case systemDefault

    public func makeConfiguration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.default
        switch self {
        case .standard:
            configuration.timeoutIntervalForRequest = 20
        case .connectionProbe:
            configuration.timeoutIntervalForRequest = 8
            configuration.timeoutIntervalForResource = 12
            configuration.waitsForConnectivity = false
        case .systemDefault:
            break
        }
        return configuration
    }
}

/// Immutable public device/endpoint metadata; credentials are intentionally absent.
public struct TransportConfiguration: Equatable, Sendable {
    public let url: URL
    public let client: String
    public let deviceName: String
    public let deviceID: String
    public let version: String
}

/// Owns an SDK client whose credentials never change after construction.
/// Authentication returns a result for the account owner to publish; no raw SDK
/// client, session or authentication mutator escapes through this API. Request/response DTOs
/// remain immutable typed SDK values for the feature owners that use them.
@MainActor
public final class JellyfinTransport: CustomStringConvertible {
    private let sdk: JellyfinClient
    public nonisolated let configuration: TransportConfiguration

    public init(
        url: URL,
        accessToken: String? = nil,
        identity: TransportClientIdentity,
        policy: TransportSessionPolicy = .standard,
        sessionDelegate: (any URLSessionDelegate)? = nil,
        sessionConfiguration: URLSessionConfiguration? = nil
    ) {
        configuration = .init(
            url: url,
            client: identity.client,
            deviceName: identity.deviceName,
            deviceID: identity.deviceID,
            version: identity.version
        )
        sdk = JellyfinClient(
            configuration: .init(
                url: url,
                accessToken: accessToken,
                client: identity.client,
                deviceName: identity.deviceName,
                deviceID: identity.deviceID,
                version: identity.version
            ),
            sessionConfiguration: sessionConfiguration ?? policy.makeConfiguration(),
            sessionDelegate: sessionDelegate
        )
    }

    public nonisolated var description: String {
        "JellyfinTransport(deviceID: " + configuration.deviceID + ")"
    }

    public var version: JellyfinClient.Version {
        sdk.version
    }

    public func send<Value: Decodable & Sendable>(
        _ request: Request<Value>,
        delegate: (any URLSessionDataDelegate)? = nil,
        configure: (@Sendable (inout URLRequest) throws -> Void)? = nil
    ) async throws -> Response<Value> {
        try Task.checkCancellation()
        let response = try await sdk.send(request, delegate: delegate, configure: configure)
        try Task.checkCancellation()
        return response
    }

    @discardableResult
    public func send(
        _ request: Request<Void>,
        delegate: (any URLSessionDataDelegate)? = nil,
        configure: (@Sendable (inout URLRequest) throws -> Void)? = nil
    ) async throws -> Response<Void> {
        try Task.checkCancellation()
        let response = try await sdk.send(request, delegate: delegate, configure: configure)
        try Task.checkCancellation()
        return response
    }

    public func url(with request: Request<some Any>, queryAPIKey: Bool = false) -> URL? {
        sdk.url(with: request, queryAPIKey: queryAPIKey)
    }

    public func url(path: String) -> URL? {
        sdk.url(path: path)
    }

    /// Authentication does not mutate this transport's credential binding.
    public func authenticate(username: String, password: String) async throws -> AuthenticationResult {
        let result = try await send(Paths.authenticateUserByName(.init(pw: password, username: username))).value
        guard result.accessToken != nil else { throw JellyfinClient.ClientError.noAccessToken }
        return result
    }

    public func authenticate(quickConnectSecret: String) async throws -> AuthenticationResult {
        let result = try await send(Paths.authenticateWithQuickConnect(.init(secret: quickConnectSecret))).value
        guard result.accessToken != nil else { throw JellyfinClient.ClientError.noAccessToken }
        return result
    }

    public struct DiscoveredServer: Equatable, Sendable {
        public let id: String
        public let name: String
        public let url: URL
    }

    public static func discover() -> AsyncThrowingStream<DiscoveredServer, any Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for try await server in JellyfinClient.discover() {
                        try Task.checkCancellation()
                        continuation.yield(.init(id: server.id, name: server.name, url: server.url))
                    }
                    continuation.finish()
                } catch is CancellationError { continuation.finish() }
                catch { continuation.finish(throwing: error) }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // Internal to the single SDK-owning transport module. The socket controller
    // owns these native objects; callers receive only typed payload publishers.
    func makeSocketSession() -> JellyfinSocket.Session {
        sdk.socket(supportsMediaControl: true, supportedCommands: [
            .displayContent, .play, .playMediaSource, .playState, .playTrailers,
            .setAudioStreamIndex, .setMaxStreamingBitrate, .setSubtitleStreamIndex
        ], playableMediaTypes: [.video]).connect(responseTimeout: .seconds(10))
    }
}
