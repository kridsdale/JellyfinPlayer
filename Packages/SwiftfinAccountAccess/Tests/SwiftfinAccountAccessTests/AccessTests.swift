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
@testable import SwiftfinAccountAccess
import SwiftfinNetworking
import Testing

@MainActor
private final class Binding { var current = true }
@MainActor
private final class Transport: AccountAccessTransport {
    struct Call { let path: String
        let method: String
        let query: [String: String]
        let body: Data?
    }

    var calls: [Call] = []
    var urlCalls: [Call] = []
    var queryKeyFlags: [Bool] = []
    var responseURL = URL(string: "https://redirect.example/jf/System/Info/Public")
    var info = PublicSystemInfo(id: "server", serverName: "Server")
    var currentUser = UserDto(id: "user", name: "User")
    var publicUsers = [UserDto(id: "public", name: "Public")]
    var branding = BrandingOptionsDto(loginDisclaimer: "Welcome")
    var boolBytes = Data("true".utf8)
    var auth = AuthenticationResult(accessToken: "fixture-token", serverID: "server", user: .init(id: "user", name: "User"))
    var authCalls: [(String, String?)] = []
    var quickInitial = QuickConnectResult(code: "123456", secret: "initial-secret")
    var quickPolls: [Result<QuickConnectResult, Failure>] = []
    var failure = false
    var blocked = false
    var gate: CheckedContinuation<Void, Never>?
    enum Failure: Error { case offline }
    private func capture(_ request: Request<some Any>) throws -> Call {
        try .init(
            path: request.url?.path ?? "",
            method: request.method.rawValue,
            query: Dictionary(uniqueKeysWithValues: (request.query ?? []).compactMap { k, v in v.map { (k, $0) } }),
            body: request.body.map { try JSONEncoder().encode($0) }
        )
    }

    private func pause() async throws {
        if blocked {
            await withCheckedContinuation { gate = $0 }
        }
        if failure {
            throw Failure.offline
        }
    }

    func value<Value: Decodable & Sendable>(for request: Request<Value>) async throws -> Value {
        try calls.append(capture(request))
        try await pause()
        if Value.self == Data.self {
            return boolBytes as! Value
        }
        let data: Data
        switch request.url?.path {
        case "/System/Info/Public": data = try JSONEncoder().encode(info)
        case "/Users/Public": data = try JSONEncoder().encode(publicUsers)
        case "/Branding/Configuration": data = try JSONEncoder().encode(branding)
        case "/Users/Me": data = try JSONEncoder().encode(currentUser)
        case "/QuickConnect/Initiate": data = try JSONEncoder().encode(quickInitial)
        case "/QuickConnect/Connect":
            let result = quickPolls.isEmpty ? QuickConnectResult(isAuthenticated: false) : try quickPolls.removeFirst().get()
            data = try JSONEncoder().encode(result)
        default: throw Failure.offline
        }
        return try JSONDecoder().decode(Value.self, from: data)
    }

    func response<Value: Decodable & Sendable>(for request: Request<Value>) async throws -> JellyfinResponse<Value> {
        try await .init(value: value(for: request), responseURL: responseURL)
    }

    func complete(_ request: Request<Void>) async throws {
        try calls.append(capture(request))
        try await pause()
    }

    func url(with request: Request<some Any>, queryAPIKey: Bool) -> URL? {
        guard let call = try? capture(request) else { return nil }
        urlCalls.append(call)
        queryKeyFlags.append(queryAPIKey)
        var result = URLComponents(string: "https://original.example/jf" + call.path)!
        result.queryItems = call.query.map { URLQueryItem(name: $0.key, value: $0.value) }
        return result.url
    }

    func url(path: String) -> URL? {
        URL(string: "https://original.example/jf" + path)
    }

    func authenticate(username: String, password: String) async throws -> AuthenticationResult {
        authCalls.append((username, password))
        try await pause()
        return auth
    }

    func authenticate(quickConnectSecret: String) async throws -> AuthenticationResult {
        authCalls.append((quickConnectSecret, nil))
        try await pause()
        return auth
    }

    func release() {
        blocked = false
        gate?.resume()
        gate = nil
    }

    func wait() async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while gate == nil {
            if .now >= deadline {
                throw Failure.offline
            }
            await Task.yield()
        }
    }
}

@MainActor
private func make(_ transport: Transport, _ binding: Binding = Binding(), serverID: String? = "server") -> AccountAccessClient {
    .init(transport: transport, expectedServerID: serverID, isCurrent: { binding.current })
}

@Test @MainActor
func `public info preserves actual response URL and expected server`() async throws {
    let transport = Transport()
    let client = make(transport)
    let result = try await client.publicInfo()
    #expect(result.value.id == "server")
    #expect(result.responseURL == transport.responseURL)
    #expect(transport.calls.first?.path == "/System/Info/Public")
    transport.info.id = "other"
    await #expect(throws: AccountAccessError.self) { try await client.publicInfo() }
}

@Test @MainActor
func `login options use one transport and preserve boolean and disclaimer fallbacks`() async throws {
    let transport = Transport()
    let client = make(transport)
    let result = try await client.loginOptions()
    #expect(Set(transport.calls.map(\.path)) == ["/Users/Public", "/Branding/Configuration", "/QuickConnect/Enabled"])
    #expect(result.users == transport.publicUsers)
    #expect(result.disclaimer == "Welcome")
    #expect(result.quickConnectEnabled)
    transport.boolBytes = Data("not-json".utf8)
    transport.branding.loginDisclaimer = ""
    let fallback = try await client.loginOptions()
    #expect(!fallback.quickConnectEnabled)
    #expect(fallback.disclaimer == nil)
}

@Test @MainActor
func `authentication validates required values without mutating transport`() async throws {
    let transport = Transport()
    let client = make(transport)
    let password = try await client.signIn(username: " entered user ", password: " entered password ")
    let quick = try await client.signIn(quickConnectSecret: "fixture-secret")
    #expect(password.userID == "user")
    #expect(password.username == "User")
    #expect(password.accessToken == "fixture-token")
    #expect(quick.user == password.user)
    #expect(transport.authCalls.count == 2)
    #expect(transport.authCalls[0].0 == " entered user ")
    #expect(transport.authCalls[0].1 == " entered password ")
    #expect(transport.authCalls[1].0 == "fixture-secret")
    #expect(transport.authCalls[1].1 == nil)
    #expect(transport.auth.accessToken == "fixture-token")
}

@Test @MainActor
func `missing authentication fields cannot become local account`() async {
    for change in 0 ..< 4 {
        let transport = Transport()
        let client = make(transport)
        switch change { case 0: transport.auth.accessToken = nil
        case 1: transport.auth.user = nil
        case 2: transport.auth.user?.id = nil
        default: transport.auth.user?.name = nil }
        await #expect(throws: AccountAccessError.self) { try await client.signIn(username: "fixture", password: "fixture") }
    }
}

@Test @MainActor
func `wrong authentication server cannot become selected server account`() async {
    let transport = Transport()
    transport.auth.serverID = "other"
    let client = make(transport)
    await #expect(throws: AccountAccessError.self) { try await client.signIn(quickConnectSecret: "fixture") }
}

@Test @MainActor
func `replaced connection rejects late authentication success and failure`() async throws {
    for failing in [false, true] {
        let transport = Transport()
        transport.blocked = true
        transport.failure = failing
        let binding = Binding()
        let client = make(transport, binding)
        let task = Task { @MainActor in try await client.signIn(username: "fixture", password: "fixture") }
        try await transport.wait()
        binding.current = false
        transport.release()
        await #expect(throws: CancellationError.self) { try await task.value }
    }
}

@Test @MainActor
func `expired binding rejects all request auth and URL ports before IO`() async {
    let transport = Transport()
    let binding = Binding()
    let client = make(transport, binding)
    binding.current = false
    await #expect(throws: CancellationError.self) { try await client.publicInfo() }
    await #expect(throws: CancellationError.self) { try await client.loginOptions() }
    await #expect(throws: CancellationError.self) { try await client.signIn(username: "fixture", password: "fixture") }
    await #expect(throws: CancellationError.self) { try await client.resetPassword(userID: "user", current: "fixture", new: "fixture") }
    #expect(throws: CancellationError.self) { try client.profileURL(userID: "user", imageTag: nil) }
    #expect(throws: CancellationError.self) { try client.splashURL() }
    #expect(transport.calls.isEmpty)
    #expect(transport.authCalls.isEmpty)
    #expect(transport.urlCalls.isEmpty)
}

@Test @MainActor
func `own user identity is exact`() async throws {
    let transport = Transport()
    let client = make(transport)
    #expect(try await client.currentUser(expectedUserID: "user").id == "user")
    transport.currentUser.id = "other"
    await #expect(throws: AccountAccessError.self) { try await client.currentUser(expectedUserID: "user") }
}

@Test @MainActor
func `exact quick connect and password commands preserve fields`() async throws {
    let transport = Transport()
    let client = make(transport)
    #expect(try await client.authorizeQuickConnect(code: "123456", userID: "selected-user"))
    transport.boolBytes = Data("bad".utf8)
    #expect(try await !client.authorizeQuickConnect(code: "123456", userID: "selected-user"))
    try await client.resetPassword(userID: "selected-user", current: "fixture-current", new: "fixture-new")
    #expect(transport.calls[0].path == "/QuickConnect/Authorize")
    #expect(transport.calls[0].method == "POST")
    #expect(transport.calls[0].query == ["code": "123456", "userId": "selected-user"])
    let password = transport.calls[2]
    #expect(password.path == "/Users/Password")
    #expect(password.method == "POST")
    #expect(password.query == ["userId": "selected-user"])
    let body = try JSONSerialization.jsonObject(with: #require(password.body)) as? [String: String]
    #expect(body == ["CurrentPw": "fixture-current", "NewPw": "fixture-new"])
}

@Test @MainActor
func `account image UR ls do not enable query authentication or make requests`() throws {
    let transport = Transport()
    let client = make(transport)
    let splash = try client.splashURL()
    let profile = try client.profileURL(userID: "selected", imageTag: "tag")
    #expect(splash?.path == "/jf/Branding/Splashscreen")
    #expect(profile?.path == "/jf/UserImage")
    #expect(transport.urlCalls[1].query == ["userId": "selected", "tag": "tag"])
    #expect(transport.queryKeyFlags == [false, false])
    #expect(transport.calls.isEmpty)
}

@Test @MainActor
func `account command replacement rejects late success or error`() async throws {
    for failing in [false, true] {
        let transport = Transport()
        transport.blocked = true
        transport.failure = failing
        let binding = Binding()
        let client = make(transport, binding)
        let task = Task { @MainActor in try await client.resetPassword(userID: "user", current: "fixture", new: "fixture") }
        try await transport.wait()
        binding.current = false
        transport.release()
        await #expect(throws: CancellationError.self) { try await task.value }
    }
}

@Test
func `redirected connection includes changed port and base path but rejects wrong endpoint`() throws {
    let initial = try #require(URL(string: "http://original.example:8096"))
    let response = try #require(URL(string: "https://redirect.example:9443/base/System/Info/Public?test=1#frag"))
    #expect(AccountConnectionPolicy.redirectedURL(initial: initial, response: response)
        .absoluteString == "https://redirect.example:9443/base")
    let sameOrigin = try #require(URL(string: "http://original.example:9096/jf/System/Info/Public"))
    #expect(AccountConnectionPolicy.redirectedURL(initial: initial, response: sameOrigin)
        .absoluteString == "http://original.example:9096/jf")
    #expect(AccountConnectionPolicy.redirectedURL(initial: initial, response: URL(string: "https://other.example/unrelated")) == initial)
    #expect(AccountConnectionPolicy.redirectedURL(initial: initial, response: nil) == initial)
}

@Test @MainActor
func `explicit entered name fallback preserves kids login without weakening strict login`() async throws {
    let transport = Transport()
    transport.auth.user?.name = nil
    let client = make(transport)
    await #expect(throws: AccountAccessError.self) { try await client.signIn(username: "Entered", password: "fixture") }
    let result = try await client.signIn(username: "Entered", password: "fixture", fallbackUsername: "Entered")
    #expect(result.userID == "user" && result.username == "Entered" && result.accessToken == "fixture-token")
    #expect(result.user.name == nil)
}

@Test @MainActor
func `server username wins over entered fallback including an existing empty name`() async throws {
    let transport = Transport()
    let client = make(transport)
    #expect(try await client.signIn(username: "Alias", password: "fixture", fallbackUsername: "Alias").username == "User")
    transport.auth.user?.name = ""
    #expect(try await client.signIn(username: "Alias", password: "fixture", fallbackUsername: "Alias").username == "")
}

@Test @MainActor
func `fallback name cannot supply missing authentication identity or cross server binding`() async {
    for missing in 0 ..< 4 {
        let transport = Transport()
        switch missing {
        case 0: transport.auth.accessToken = nil
        case 1: transport.auth.user = nil
        case 2: transport.auth.user?.id = nil
        default: transport.auth.serverID = "other"
        }
        let client = make(transport)
        await #expect(throws: AccountAccessError.self) {
            try await client.signIn(username: "Entered", password: "fixture", fallbackUsername: "Entered")
        }
    }
}

@Test @MainActor
func `fallback login still rejects A replaced connection after the await`() async throws {
    let transport = Transport()
    transport.auth.user?.name = nil
    transport.blocked = true
    let binding = Binding()
    let client = make(transport, binding)
    let operation = Task { @MainActor in
        try await client.signIn(username: "Entered", password: "fixture", fallbackUsername: "Entered")
    }
    try await transport.wait()
    binding.current = false
    transport.release()
    await #expect(throws: CancellationError.self) { try await operation.value }
}

@MainActor
private final class PollClock {
    var sleeps: [Duration] = []
    var continuation: CheckedContinuation<Void, Never>?
    var entered = false
    var cancelled = false
    func wait() async {
        await withCheckedContinuation { continuation = $0 }
    }

    func release() {
        continuation?.resume()
        continuation = nil
    }
}

@MainActor
private func settle(_ condition: () -> Bool) async {
    for _ in 0 ..< 2000 {
        if condition() {
            return
        }
        await Task.yield()
    }
    #expect(condition())
}

@Suite("Connection-bound Quick Connect")
@MainActor
struct QuickConnectContracts {
    private func access(_ transport: Transport, _ binding: Binding? = nil) -> AccountAccessClient {
        .init(transport: transport, expectedServerID: "server", isCurrent: { binding?.current ?? true })
    }

    private func policy(_ clock: PollClock, maximum: Int = 4, tolerance: Int = 5) -> QuickConnectPollingPolicy {
        .init(maximumPolls: maximum, failureTolerance: tolerance, sleep: { clock.sleeps.append($0) })
    }

    private func collect(_ client: AccountAccessClient, _ policy: QuickConnectPollingPolicy) async throws -> [AccountQuickConnectEvent] {
        var events: [AccountQuickConnectEvent] = []
        for try await event in client.quickConnectEvents(policy: policy) {
            events.append(event)
        }
        return events
    }

    @Test
    func `production polling defaults preserve pinned SDK cadence and limits`() {
        let policy = QuickConnectPollingPolicy()
        #expect(policy.interval == .seconds(5) && policy.maximumPolls == 200 && policy.failureTolerance == 5)
    }

    @Test
    func `polling and approved secret keep the original transport through final sign in`() async throws {
        let t = Transport(), clock = PollClock()
        t.quickPolls = [.success(.init(isAuthenticated: false)), .success(.init(isAuthenticated: true, secret: "approved-secret"))]
        let client = access(t)
        let events = try await collect(client, policy(clock))
        #expect(events == [.polling(code: "123456"), .authenticated(secret: "approved-secret")])
        #expect(t.calls.map(\.path) == ["/QuickConnect/Initiate", "/QuickConnect/Connect", "/QuickConnect/Connect"])
        #expect(t.calls.dropFirst().allSatisfy { $0.query == ["secret": "initial-secret"] })
        #expect(clock.sleeps == [.seconds(5)])
        _ = try await client.signIn(quickConnectSecret: "approved-secret")
        #expect(t.authCalls.count == 1 && t.authCalls[0].0 == "approved-secret")
    }

    @Test
    func `missing initial code or secret fails before polling`() async {
        for initial in [QuickConnectResult(code: "123456"), QuickConnectResult(secret: "initial-secret")] {
            let t = Transport(), clock = PollClock()
            t.quickInitial = initial
            await #expect(throws: AccountQuickConnectError.retrievingCodeFailed) { try await collect(access(t), policy(clock)) }
            #expect(t.calls.map(\.path) == ["/QuickConnect/Initiate"] && clock.sleeps.isEmpty)
        }
    }

    @Test
    func `successful pending response resets consecutive failures before authorization`() async throws {
        let t = Transport(), clock = PollClock()
        t.quickPolls = [
            .failure(.offline),
            .success(.init(isAuthenticated: false)),
            .failure(.offline),
            .success(.init(isAuthenticated: true, secret: "approved"))
        ]
        let events = try await collect(access(t), policy(clock, tolerance: 1))
        #expect(events.last == .authenticated(secret: "approved") && clock.sleeps.count == 3 && t.calls.count == 5)
    }

    @Test
    func `failure limit and poll limit preserve separate terminal errors`() async {
        let t = Transport(), clock = PollClock()
        t.quickPolls = [.failure(.offline), .failure(.offline), .success(.init(isAuthenticated: true, secret: "unused"))]
        await #expect(throws: Transport.Failure.self) { try await collect(access(t), policy(clock, tolerance: 1)) }
        #expect(t.calls.count == 3 && clock.sleeps.count == 1 && t.quickPolls.count == 1)
        let pending = Transport(), pendingClock = PollClock()
        // An authenticated response without a secret remains pending, as in the SDK.
        pending.quickPolls = [.success(.init(isAuthenticated: true))]
        await #expect(throws: AccountQuickConnectError.maxPollingHit) {
            try await collect(access(pending), policy(pendingClock, maximum: 2))
        }
        #expect(pending.calls.count == 3 && pendingClock.sleeps.count == 2)
    }

    @Test
    func `already expired connection starts no Quick Connect requests`() async {
        let t = Transport(), binding = Binding(), clock = PollClock()
        binding.current = false
        await #expect(throws: CancellationError.self) { try await collect(access(t, binding), policy(clock)) }
        #expect(t.calls.isEmpty && clock.sleeps.isEmpty)
    }

    @Test
    func `connection replacement rejects delayed initial success and error before polling`() async {
        for failure in [false, true] {
            let t = Transport(), binding = Binding(), clock = PollClock()
            t.blocked = true
            t.failure = failure
            let client = access(t, binding)
            let task = Task { try await collect(client, policy(clock)) }
            defer { task.cancel()
                t.release()
            }
            await settle { t.gate != nil }
            binding.current = false
            t.release()
            await #expect(throws: CancellationError.self) { try await task.value }
            #expect(t.calls.count == 1 && clock.sleeps.isEmpty)
        }
    }

    @Test
    func `replacement during the sleep prevents the next silent poll`() async {
        let t = Transport(), binding = Binding(), clock = PollClock()
        let client = access(t, binding)
        let p = QuickConnectPollingPolicy(maximumPolls: 3, sleep: { _ in await clock.wait() })
        let task = Task { try await collect(client, p) }
        defer { task.cancel()
            clock.release()
        }
        await settle { clock.continuation != nil }
        binding.current = false
        clock.release()
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(t.calls.map(\.path) == ["/QuickConnect/Initiate", "/QuickConnect/Connect"])
    }

    @Test
    func `consumer cancellation cancels producer sleep without another request`() async {
        let t = Transport(), clock = PollClock()
        let client = access(t)
        let p = QuickConnectPollingPolicy(sleep: { _ in
            clock.entered = true
            do { try await Task.sleep(for: .seconds(100)) }
            catch { clock.cancelled = true
                throw error
            }
        })
        let task = Task { try await collect(client, p) }
        defer { task.cancel() }
        await settle { clock.entered }
        task.cancel()
        _ = try? await task.value
        await settle { clock.cancelled }
        #expect(t.calls.count == 2)
    }

    @Test
    func `replacement after approval rejects authentication through captured client`() async throws {
        let t = Transport(), binding = Binding(), clock = PollClock()
        t.quickPolls = [.success(.init(isAuthenticated: true, secret: "approved"))]
        let client = access(t, binding)
        #expect(try await collect(client, policy(clock)).last == .authenticated(secret: "approved"))
        binding.current = false
        await #expect(throws: CancellationError.self) { try await client.signIn(quickConnectSecret: "approved") }
        #expect(t.authCalls.isEmpty)
    }
}
