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
        var requestBodies: [Data] = []
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
        let body = Self.body(of: capturedRequest)
        let reply = Self.state.withLock { state in
            state.requests.append(capturedRequest)
            state.requestBodies.append(body)
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

    private static func body(of request: URLRequest) -> Data {
        if let body = request.httpBody {
            return body
        }
        guard let stream = request.httpBodyStream else { return Data() }
        stream.open()
        defer { stream.close() }
        var result = Data()
        var buffer = [UInt8](repeating: 0, count: 1024)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count > 0 else { break }
            result.append(contentsOf: buffer.prefix(count))
        }
        return result
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

    @Test
    func `password authentication sends the SDK body without mutating existing request credentials`() async throws {
        let client = transport(token: "initial-token", body: #"{"AccessToken":"returned-token","User":{"Id":"kid"}}"#)
        let result = try await client.authenticate(username: "synthetic-kid", password: "synthetic-password")
        #expect(result.accessToken == "returned-token" && result.user?.id == "kid")
        _ = try await client.send(Paths.getPublicSystemInfo)
        let requests = StubProtocol.state.withLock { $0.requests }
        #expect(requests.count == 2 && requests[0].url?.path == "/base/Users/AuthenticateByName")
        #expect(requests[0].httpMethod == "POST")
        let body = try JSONSerialization.jsonObject(with: StubProtocol.state.withLock { $0.requestBodies[0] }) as? [String: String]
        #expect(body == ["Username": "synthetic-kid", "Pw": "synthetic-password"])
        #expect(requests.allSatisfy { $0.value(forHTTPHeaderField: "Authorization")?.contains("initial-token") == true })
        let nextAuthorization = try #require(requests[1].value(forHTTPHeaderField: "Authorization"))
        #expect(!nextAuthorization.contains("returned-token"))
        #expect(!String(describing: client).contains("returned-token"))
    }

    @Test
    func `Quick Connect authentication returns credentials without rebinding the anonymous transport`() async throws {
        let client = transport(body: #"{"AccessToken":"quick-token","User":{"Id":"kid"}}"#)
        let result = try await client.authenticate(quickConnectSecret: "synthetic-secret")
        _ = try await client.send(Paths.getPublicSystemInfo)
        let requests = StubProtocol.state.withLock { $0.requests }
        #expect(result.accessToken == "quick-token")
        let body = try JSONSerialization.jsonObject(with: StubProtocol.state.withLock { $0.requestBodies[0] }) as? [String: String]
        #expect(body == ["Secret": "synthetic-secret"])
        #expect(requests[0].url?.path == "/base/Users/AuthenticateWithQuickConnect")
        #expect(requests.allSatisfy { $0.value(forHTTPHeaderField: "Authorization")?.contains("quick-token") == false })
    }

    @Test
    func `successful HTTP authentication without a token is rejected and cannot replace credentials`() async {
        let client = transport(token: "initial-token", body: #"{"User":{"Id":"kid"}}"#)
        do { _ = try await client.authenticate(username: "kid", password: "synthetic")
            Issue.record("Missing access token must fail")
        } catch { #expect(error is JellyfinClient.ClientError) }
        #expect(StubProtocol.state
            .withLock { $0.requests[0].value(forHTTPHeaderField: "Authorization")?.contains("initial-token") == true })
    }

    @Test
    func `exact account endpoint and token replacements invalidate only the cached transport`() throws {
        var builds = 0
        let cache = AccountTransportCache { url, token in
            builds += 1
            return JellyfinTransport(url: url, accessToken: token, identity: identity)
        }
        let url = try #require(URL(string: "https://unit.example.test/base"))
        let original = cache.client(url: url, serverID: "server", userID: "kid", accessToken: "old-token")
        #expect(cache.client(url: url, serverID: "server", userID: "kid", accessToken: "old-token") === original && builds == 1)
        let changed = cache.client(url: url, serverID: "server", userID: "kid", accessToken: "new-token")
        #expect(changed !== original && builds == 2)
        let oldURL = try #require(original.url(with: Paths.getPublicSystemInfo, queryAPIKey: true))
        let newURL = try #require(changed.url(with: Paths.getPublicSystemInfo, queryAPIKey: true))
        #expect(oldURL.query?.contains("old-token") == true && newURL.query?.contains("new-token") == true)
        let moved = try cache.client(
            url: #require(URL(string: "https://other.example.test/base")),
            serverID: "server",
            userID: "kid",
            accessToken: "new-token"
        )
        #expect(moved !== changed && builds == 3)
        _ = cache.client(url: url, serverID: "other-server", userID: "kid", accessToken: "new-token")
        _ = cache.client(url: url, serverID: "other-server", userID: "other-kid", accessToken: "new-token")
        #expect(builds == 5)
        cache.invalidate()
        _ = cache.client(url: url, serverID: "other-server", userID: "other-kid", accessToken: "new-token")
        #expect(builds == 6 && !String(describing: cache).contains("new-token"))
    }

    @Test
    func `overlapping authentication and metadata cannot rebind an existing transport`() async throws {
        let client = transport(token: "initial-token", body: #"{"AccessToken":"returned-token","User":{"Id":"kid"},"Id":"server"}"#)
        async let authentication = client.authenticate(username: "kid", password: "synthetic")
        async let metadata = client.send(Paths.getPublicSystemInfo)
        let (result, info) = try await (authentication, metadata)
        #expect(result.accessToken == "returned-token" && info.value.id == "server")
        _ = try await client.send(Paths.getPublicSystemInfo)
        let requests = StubProtocol.state.withLock { $0.requests }
        #expect(requests.count == 3)
        #expect(requests.allSatisfy { $0.value(forHTTPHeaderField: "Authorization")?.contains("initial-token") == true })
        #expect(requests.allSatisfy { $0.value(forHTTPHeaderField: "Authorization")?.contains("returned-token") == false })
    }

    @Test(arguments: [false, true])
    func `factory reentry cannot republish an invalidated or replacement cache`(_ replace: Bool) throws {
        let url = try #require(URL(string: "https://unit.example.test/base"))
        var builds = 0
        var action: (@MainActor () -> Void)?
        var replacement: JellyfinTransport?
        let cache = AccountTransportCache { url, token in
            builds += 1
            let current = action
            action = nil
            current?()
            return JellyfinTransport(url: url, accessToken: token, identity: identity)
        }
        action = { [weak cache] in
            if replace {
                replacement = cache?.client(url: url, serverID: "server", userID: "kid", accessToken: "new-token")
            } else {
                cache?.invalidate()
            }
        }
        let original = cache.client(url: url, serverID: "server", userID: "kid", accessToken: "old-token")
        let current = cache.client(url: url, serverID: "server", userID: "kid", accessToken: replace ? "new-token" : "old-token")
        #expect(builds == 2 && original !== current)
        if replace {
            #expect(current === replacement)
        }
        cache.invalidate()
    }
}
