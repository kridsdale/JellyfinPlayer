//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation
import SwiftfinAccountModels
import SwiftfinConnections
import Testing

@MainActor
private final class Probe: ServerConnectionProbing {
    enum Failure: Error { case offline }
    var replies: [String: Result<String?, Failure>] = [:]
    var requestedIDs: [String] = []
    var tokens: [String?] = []
    func serverID(at connection: ServerConnection, accessToken: String?) async throws -> String? {
        requestedIDs.append(connection.id)
        tokens.append(accessToken)
        return try (replies[connection.id] ?? .failure(.offline)).get()
    }
}

@MainActor
private final class DeferredProbe: ServerConnectionProbing {
    var continuation: CheckedContinuation<String?, any Error>?
    var requestedIDs: [String] = []
    func serverID(at connection: ServerConnection, accessToken: String?) async throws -> String? {
        requestedIDs.append(connection.id)
        return try await withCheckedThrowingContinuation { continuation = $0 }
    }
}

@Suite(.serialized) @MainActor
struct ConnectionResolutionContracts {
    private func connection(
        _ id: String,
        priority: Int,
        interface: ServerConnection.Interface = .any,
        ssids: [String] = []
    ) -> ServerConnection {
        .init(id: id, name: id, url: URL(string: "https://\(id).example.test")!, interface: interface, wifiSSIDs: ssids, priority: priority)
    }

    private let wifi = NetworkConnectionContext(isSatisfied: true, interface: .wifi, wifiSSID: "Home")

    @Test
    func `unavailable network and unmatched interface never send probes`() async throws {
        let p = Probe()
        let cellular = connection("cell", priority: 0, interface: .cellular)
        let offline = try await ServerConnectionResolver.resolve(
            connections: [cellular],
            accessToken: nil,
            expectedServerID: "server",
            context: .unavailable,
            probe: p
        )
        #expect(offline == .unreachable([]))
        let unmatched = try await ServerConnectionResolver.resolve(
            connections: [cellular],
            accessToken: nil,
            expectedServerID: "server",
            context: wifi,
            probe: p
        )
        #expect(unmatched == .unreachable([]))
        #expect(p.requestedIDs.isEmpty)
    }

    @Test
    func `priority and SSID scope choose the first verified endpoint and retain the supplied token`() async throws {
        let p = Probe()
        let remote = connection("remote", priority: 8)
        let wrongSSID = connection("otherwifi", priority: 0, interface: .wifi, ssids: ["Office"])
        let home = connection("home", priority: 4, interface: .wifi, ssids: ["home"])
        p.replies["home"] = .success("server")
        p.replies["remote"] = .success("server")
        let result = try await ServerConnectionResolver.resolve(
            connections: [remote, wrongSSID, home],
            accessToken: "synthetic test token",
            expectedServerID: "server",
            context: wifi,
            probe: p
        )
        guard case let .connected(chosen) = result else { Issue.record("Expected a connected endpoint")
            return
        }
        #expect(chosen.id == "home" && chosen.priority == 1)
        #expect(p.requestedIDs == ["home"] && p.tokens == ["synthetic test token"])
    }

    @Test
    func `failed and wrong-server endpoints cannot prevent a later exact identity match`() async throws {
        let p = Probe()
        let connections = [
            connection("offline", priority: 0),
            connection("imposter", priority: 1),
            connection("missing", priority: 2),
            connection("real", priority: 3)
        ]
        p.replies["imposter"] = .success("other-server")
        p.replies["missing"] = .success(nil)
        p.replies["real"] = .success("server")
        let result = try await ServerConnectionResolver.resolve(
            connections: connections,
            accessToken: nil,
            expectedServerID: "server",
            context: wifi,
            probe: p
        )
        #expect(result == .connected(connections[3]))
        #expect(p.requestedIDs == ["offline", "imposter", "missing", "real"])
    }

    @Test
    func `unreachable results contain only the ordered eligible candidates`() async throws {
        let p = Probe()
        let cell = connection("cell", priority: 0, interface: .cellular)
        let remote = connection("remote", priority: 9)
        let home = connection("home", priority: 3, interface: .wifi)
        let normalized = ServerConnection.ordered([cell, remote, home])
        let result = try await ServerConnectionResolver.resolve(
            connections: [cell, remote, home],
            accessToken: nil,
            expectedServerID: "server",
            context: wifi,
            probe: p
        )
        #expect(result == .unreachable(normalized.filter { $0.matches(wifi) }))
        #expect(p.requestedIDs == ["home", "remote"])
    }

    @Test
    func `manual test rejects missing mismatched and case-different server IDs`() async {
        let p = Probe()
        let c = connection("home", priority: 0)
        for reply in [nil, "other", "SERVER"] as [String?] {
            p.replies[c.id] = .success(reply)
            do {
                try await ServerConnectionResolver.test(connection: c, accessToken: nil, expectedServerID: "server", probe: p)
                Issue.record("Unverified server must fail")
            } catch {
                #expect(error as? ServerConnectionProbeError == .serverMismatch)
            }
        }
    }

    @Test
    func `already cancelled resolution performs no transport work`() async {
        let p = Probe()
        let c = connection("home", priority: 0)
        let task = Task { try await ServerConnectionResolver.resolve(
            connections: [c],
            accessToken: nil,
            expectedServerID: "server",
            context: wifi,
            probe: p
        ) }
        task.cancel()
        do { _ = try await task.value
            Issue.record("Expected cancellation")
        } catch { #expect(error is CancellationError) }
        #expect(p.requestedIDs.isEmpty)
    }

    @Test
    func `noncooperating success after cancellation cannot select or probe a fallback`() async throws {
        try await cancellationAfterProbe(succeeds: true)
    }

    @Test
    func `noncooperating failure after cancellation cannot probe a fallback`() async throws {
        try await cancellationAfterProbe(succeeds: false)
    }

    private func cancellationAfterProbe(succeeds: Bool) async throws {
        let p = DeferredProbe()
        let candidates = [connection("home", priority: 0), connection("fallback", priority: 1)]
        let task = Task { try await ServerConnectionResolver.resolve(
            connections: candidates,
            accessToken: nil,
            expectedServerID: "server",
            context: wifi,
            probe: p
        ) }
        for _ in 0 ..< 100 where p.continuation == nil {
            await Task.yield()
        }
        let continuation = try #require(p.continuation)
        task.cancel()
        if succeeds {
            continuation.resume(returning: "server")
        } else {
            continuation.resume(throwing: Probe.Failure.offline)
        }
        do { _ = try await task.value
            Issue.record("Expected cancellation")
        } catch { #expect(error is CancellationError) }
        #expect(p.requestedIDs == ["home"])
    }
}
