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
import SwiftfinItemMetadata
import SwiftfinNetworking
import Testing

@MainActor
private final class ProgramRefreshBinding { var current = true }
@MainActor
private final class ProgramRefreshGate {
    var continuation: CheckedContinuation<Void, Never>?
    var waits: [Duration] = []
    func wait(_ duration: Duration) async {
        waits.append(duration)
        await withCheckedContinuation { continuation = $0 }
    }

    func finish() {
        continuation?.resume()
        continuation = nil
    }
}

@MainActor
private final class ProgramRefreshSender: JellyfinRequestSending {
    var paths: [String] = []
    var queries: [[String: String]] = []
    var gate: ProgramRefreshGate?
    func value<Value: Decodable & Sendable>(for request: Request<Value>) async throws -> Value {
        #expect(request.method == .get && request.body == nil)
        paths.append(request.url?.path ?? "")
        queries.append(Dictionary(uniqueKeysWithValues: (request.query ?? []).compactMap { key, value in value.map { (key, $0) } }))
        if let gate {
            await gate.wait(.zero)
        }
        return try JSONDecoder().decode(Value.self, from: Data(#"{"Id":"plugin-result","Name":"Synthetic result"}"#.utf8))
    }

    func complete(_ request: Request<Void>) async throws {
        Issue.record("Unexpected write request")
    }
}

@MainActor
private func settleProgramRefresh(_ predicate: () -> Bool) async throws {
    for _ in 0 ..< 2000 {
        if predicate() {
            return
        }
        await Task.yield()
    }
    try #require(predicate())
}

@MainActor
struct ProgramMetadataRefreshContracts {
    private let now = Date(timeIntervalSince1970: 1000)
    private func client(_ sender: ProgramRefreshSender, _ binding: ProgramRefreshBinding = .init()) -> ItemMetadataClient {
        .init(
            executor: .init(sender: sender, isCurrent: { binding.current }),
            userID: "exact-user",
            bindingID: .init(transport: ObjectIdentifier(sender), userID: "exact-user")
        )
    }

    @Test
    func `delay preserves grace minimum and fractional seconds`() throws {
        #expect(try ProgramMetadataRefresh.delay(after: now.addingTimeInterval(-100), comparedTo: now) == .seconds(1))
        #expect(try ProgramMetadataRefresh.delay(after: now, comparedTo: now) == .seconds(1))
        #expect(try ProgramMetadataRefresh.delay(after: now.addingTimeInterval(0.25), comparedTo: now) == .seconds(1.25))
        #expect(try ProgramMetadataRefresh.delay(after: now.addingTimeInterval(10), comparedTo: now) == .seconds(11))
    }

    @Test
    func `invalid and unrepresentable deadlines are rejected before waiting`() async throws {
        let sender = ProgramRefreshSender(), gate = ProgramRefreshGate(), metadata = client(sender)
        for value in [Double.nan, Double.infinity, -Double.infinity, 1e30] {
            do { _ = try await metadata.item(
                id: "requested",
                afterProgramEnd: Date(timeIntervalSince1970: value),
                comparedTo: now,
                wait: gate.wait
            )
            Issue.record("Invalid deadline accepted")
            } catch { #expect(error is ProgramMetadataRefreshError) }
        }
        #expect(sender.paths.isEmpty && gate.waits.isEmpty)
    }

    @Test
    func `wait precedes exact bound read and preserves plugin response id`() async throws {
        let sender = ProgramRefreshSender(), gate = ProgramRefreshGate(), metadata = client(sender)
        let task = Task { try await metadata.item(
            id: "requested",
            afterProgramEnd: now.addingTimeInterval(10),
            comparedTo: now,
            wait: gate.wait
        ) }
        defer { task.cancel()
            gate.finish()
        }
        try await settleProgramRefresh { gate.continuation != nil }
        #expect(sender.paths.isEmpty && gate.waits == [.seconds(11)])
        gate.finish()
        let result = try await task.value
        #expect(sender.paths == ["/Items/requested"] && sender.queries == [["userId": "exact-user"]])
        #expect(result.id == "plugin-result" && result.name == "Synthetic result")
    }

    @Test
    func `account replacement while waiting performs no read`() async throws {
        let sender = ProgramRefreshSender(), gate = ProgramRefreshGate(), binding = ProgramRefreshBinding(), metadata = client(
            sender,
            binding
        )
        let task = Task { try await metadata.item(id: "requested", afterProgramEnd: now, comparedTo: now, wait: gate.wait) }
        defer { task.cancel()
            gate.finish()
        }
        try await settleProgramRefresh { gate.continuation != nil }
        binding.current = false
        gate.finish()
        do { _ = try await task.value
            Issue.record("Replaced binding returned a value")
        } catch { #expect(error is CancellationError) }
        #expect(sender.paths.isEmpty)
    }

    @Test
    func `cancelled noncooperating wait cannot proceed to io`() async throws {
        let sender = ProgramRefreshSender(), gate = ProgramRefreshGate(), metadata = client(sender)
        let task = Task { try await metadata.item(id: "requested", afterProgramEnd: now, comparedTo: now, wait: gate.wait) }
        defer { task.cancel()
            gate.finish()
        }
        try await settleProgramRefresh { gate.continuation != nil }
        task.cancel()
        gate.finish()
        do { _ = try await task.value
            Issue.record("Cancelled wait returned a value")
        } catch { #expect(error is CancellationError) }
        #expect(sender.paths.isEmpty)
    }

    @Test
    func `already cancelled caller performs no wait or read`() async {
        let sender = ProgramRefreshSender(), gate = ProgramRefreshGate(), metadata = client(sender)
        let task = Task { withUnsafeCurrentTask { $0?.cancel() }
            return try await metadata.item(id: "requested", afterProgramEnd: now, comparedTo: now, wait: gate.wait)
        }
        do { _ = try await task.value
            Issue.record("Cancelled caller returned a value")
        } catch { #expect(error is CancellationError) }
        #expect(gate.waits.isEmpty && sender.paths.isEmpty)
    }

    @Test
    func `wait error prevents a metadata request`() async {
        let sender = ProgramRefreshSender(), metadata = client(sender)
        do { _ = try await metadata.item(id: "requested", afterProgramEnd: now, comparedTo: now) { _ in throw CancellationError() }
            Issue.record("Failed wait returned a value")
        } catch { #expect(error is CancellationError) }
        #expect(sender.paths.isEmpty)
    }

    @Test
    func `account replacement during io discards the returned payload`() async throws {
        let sender = ProgramRefreshSender(), gate = ProgramRefreshGate(), binding = ProgramRefreshBinding(), metadata = client(
            sender,
            binding
        )
        sender.gate = gate
        let task = Task { try await metadata.item(id: "requested", afterProgramEnd: now, comparedTo: now, wait: { _ in }) }
        defer { task.cancel()
            gate.finish()
        }
        try await settleProgramRefresh { gate.continuation != nil }
        binding.current = false
        gate.finish()
        do { _ = try await task.value
            Issue.record("Late replaced-account payload returned")
        } catch { #expect(error is CancellationError) }
        #expect(sender.paths.count == 1)
    }
}
