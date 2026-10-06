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
import os
import SwiftfinNetworking
import Testing

private final class StubProtocol: URLProtocol {
    struct State: Sendable {
        var body = Data()
        var status = 200
        var requests: [URLRequest] = []
    }

    static let state = OSAllocatedUnfairLock(initialState: State())
    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        let capturedRequest = request
        let reply = Self.state.withLock { state in
            state.requests.append(capturedRequest)
            return (state.status, state.body)
        }
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: reply.0,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: reply.1)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

@Suite(.serialized) @MainActor
struct TransportContracts {
    private let identity = TransportClientIdentity(platform: "tvOS", deviceName: "TV", vendorID: "synthetic-device", version: "1.0")
    private func transport(
        token: String? = nil,
        body: String = #"{"Id":"server","ServerName":"Test","Version":"10.11.0"}"#,
        status: Int = 200
    ) -> JellyfinTransport {
        StubProtocol.state.withLock { $0 = .init(body: Data(body.utf8), status: status) }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubProtocol.self]
        return JellyfinTransport(
            url: URL(string: "https://unit.example.test/base")!,
            accessToken: token,
            identity: identity,
            sessionConfiguration: configuration
        )
    }

    @Test
    func `installed device identity formatting and session policies retain original values`() {
        let device = TransportClientIdentity(
            platform: "tvOS",
            deviceName: "Kevín TV 🖥",
            vendorID: "vendor",
            version: "1.0",
            locale: Locale(identifier: "en_US")
        )
        #expect(device.client == "Swiftfin tvOS" && device.deviceID == "tvOS_vendor" && device.version == "1.0")
        #expect(device.deviceName == "KevinTV")
        let first = TransportSessionPolicy.standard.makeConfiguration()
        let second = TransportSessionPolicy.standard.makeConfiguration()
        #expect(first !== second && first.timeoutIntervalForRequest == 20)
        first.timeoutIntervalForRequest = 3
        #expect(second.timeoutIntervalForRequest == 20)
        let probe = TransportSessionPolicy.connectionProbe.makeConfiguration()
        #expect(probe.timeoutIntervalForRequest == 8 && probe.timeoutIntervalForResource == 12 && !probe.waitsForConnectivity)
        #expect(TransportSessionPolicy.systemDefault.makeConfiguration().timeoutIntervalForRequest == URLSessionConfiguration.default
            .timeoutIntervalForRequest)
    }

    @Test
    func `actual SDK request keeps endpoint identity authorization and typed JSON decoding`() async throws {
        let client = transport(token: "synthetic-token")
        let response = try await client.send(Paths.getPublicSystemInfo)
        #expect(response.value.id == "server" && response.value.serverName == "Test")
        let request = try #require(StubProtocol.state.withLock { $0.requests.first })
        #expect(request.url?.path == "/base/System/Info/Public")
        let auth = try #require(request.value(forHTTPHeaderField: "Authorization"))
        #expect(auth.contains("synthetic-token") && auth.contains("tvOS_synthetic-device") && auth.contains("Swiftfin tvOS"))
        #expect(client.configuration.deviceName == "TV")
        #expect(!String(describing: client).contains("synthetic-token"))
    }

    @Test
    func `anonymous and authenticated clients do not share mutable SDK credentials`() async throws {
        let authenticated = transport(token: "synthetic-token")
        let anonymous = transport()
        _ = try await authenticated.send(Paths.getPublicSystemInfo)
        _ = try await anonymous.send(Paths.getPublicSystemInfo)
        let requests = StubProtocol.state.withLock { $0.requests }
        #expect(requests.count == 2)
        #expect(requests[0].value(forHTTPHeaderField: "Authorization")?.contains("synthetic-token") == true)
        #expect(requests[1].value(forHTTPHeaderField: "Authorization")?.contains("synthetic-token") == false)
    }

    @Test
    func `URL construction retains base paths query merging and opt-in API keys`() throws {
        let client = transport(token: "synthetic-token")
        let path = try #require(client.url(path: "/Videos/item/stream?Static=true"))
        #expect(path.path == "/base/Videos/item/stream" && path.query == "Static=true")
        let plain = try #require(client.url(with: Paths.getPublicSystemInfo))
        #expect(!plain.absoluteString.contains("synthetic-token"))
        let keyed = try #require(client.url(with: Paths.getPublicSystemInfo, queryAPIKey: true))
        #expect(URLComponents(url: keyed, resolvingAgainstBaseURL: false)?.queryItems?.contains(.init(
            name: "ApiKey",
            value: "synthetic-token"
        )) == true)
    }

    @Test
    func `HTTP denial stays a throwing response and cannot produce typed metadata`() async {
        let client = transport(body: #"{"error":"denied"}"#, status: 401)
        do { _ = try await client.send(Paths.getPublicSystemInfo)
            Issue.record("Denied request must fail")
        } catch { #expect(StubProtocol.state.withLock { $0.requests.count } == 1) }
    }

    @Test
    func `already cancelled caller cannot issue a native HTTP request`() async {
        let client = transport()
        let task = Task { try await client.send(Paths.getPublicSystemInfo) }
        task.cancel()
        do { _ = try await task.value
            Issue.record("Expected cancellation")
        } catch { #expect(error is CancellationError) }
        #expect(StubProtocol.state.withLock { $0.requests.isEmpty })
    }
}
