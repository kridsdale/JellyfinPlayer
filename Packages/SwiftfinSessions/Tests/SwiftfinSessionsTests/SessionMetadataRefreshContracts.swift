//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//
import Foundation
import SwiftfinSessions
import Testing

@MainActor
private final class RefreshFixture {
    var date = Date(timeIntervalSince1970: 1000)
    var trace: [String] = []
    var pending: [String: CheckedContinuation<Void, Never>] = [:]
    var current = true
    var onClock: (@MainActor () -> Void)?
    func wait(_ id: String) async {
        await withCheckedContinuation { pending[id] = $0 }
    }

    func release(_ id: String) throws {
        let removed = pending.removeValue(forKey: id)
        let continuation = try #require(removed)
        continuation.resume()
    }

    func clock() -> Date {
        onClock?()
        return date
    }

    func clean() {
        onClock = nil
        let continuations = Array(pending.values)
        pending = [:]
        for continuation in continuations {
            continuation.resume()
        }
    }
}

@Suite(.serialized) @MainActor
struct SessionMetadataRefreshContracts {
    private enum Failure: Error { case expected, timeout }

    private func waitUntil(_ predicate: () -> Bool) async throws {
        for _ in 0 ..< 10000 {
            if predicate() {
                return
            }
            await Task.yield()
        }
        throw Failure.timeout
    }

    private func settle() async {
        for _ in 0 ..< 100 {
            await Task.yield()
        }
    }

    private func owner(_ f: RefreshFixture, age: TimeInterval = 100, capacity: Int = 16) -> SessionMetadataRefresh<String> {
        .init(maximumAge: age, capacity: capacity, now: { f.clock() })
    }

    private func request(
        _ owner: SessionMetadataRefresh<String>,
        _ f: RefreshFixture,
        scope: String,
        force: Bool = false,
        gate: String? = nil
    ) -> Bool {
        owner.request(scope: scope, force: force, isCurrent: { f.current }, operation: { checkpoint in
            f.trace.append("start-" + scope)
            if let gate {
                await f.wait(gate)
            }
            try checkpoint()
            f.trace.append("commit-" + scope)
        }, didRefresh: { _ in f.trace.append("fresh-" + scope) }, didFail: { _ in f.trace.append("failed-" + scope) })
    }

    @Test
    func `independent accounts strict age boundary and clock rollback`() async throws {
        let f = RefreshFixture()
        defer { f.clean() }
        let o = owner(f)
        #expect(request(o, f, scope: "A"))
        try await waitUntil { f.trace.contains("fresh-A") }
        #expect(request(o, f, scope: "B"))
        try await waitUntil { f.trace.contains("fresh-B") }
        f.date = Date(timeIntervalSince1970: 1100)
        #expect(!request(o, f, scope: "A"))
        f.date = Date(timeIntervalSince1970: 900)
        #expect(!request(o, f, scope: "A"))
        f.date = Date(timeIntervalSince1970: 1100.001)
        #expect(request(o, f, scope: "A"))
        try await waitUntil { f.trace.filter { $0 == "fresh-A" }.count == 2 }
    }

    @Test
    func `forced refresh uses completion time and failure does not become fresh`() async throws {
        let f = RefreshFixture()
        defer { f.clean() }
        let o = owner(f)
        o.request(scope: "A", isCurrent: { true }, operation: { _ in throw Failure.expected }, didFail: { _ in f.trace.append("failed") })
        try await waitUntil { f.trace == ["failed"] }
        #expect(request(o, f, scope: "A", gate: "A"))
        try await waitUntil { f.pending["A"] != nil }
        f.date = Date(timeIntervalSince1970: 5000)
        try f.release("A")
        try await waitUntil { f.trace.contains("fresh-A") }
        #expect(!request(o, f, scope: "A"))
        #expect(request(o, f, scope: "A", force: true))
        try await waitUntil { f.trace.filter { $0 == "fresh-A" }.count == 2 }
    }

    @Test
    func `cancellation checkpoint stops the next commit after noncooperating await`() async throws {
        let f = RefreshFixture()
        defer { f.clean() }
        let o = owner(f)
        o.request(scope: "A", isCurrent: { true }, operation: { checkpoint in
            f.trace.append("first")
            await f.wait("A")
            try checkpoint()
            f.trace.append("second")
        }, didRefresh: { _ in f.trace.append("fresh") }, didFail: { _ in f.trace.append("failed") })
        try await waitUntil { f.pending["A"] != nil }
        o.cancel()
        try f.release("A")
        await settle()
        #expect(f.trace == ["first"])
        #expect(request(o, f, scope: "A"))
        try await waitUntil { f.trace.contains("fresh-A") }
    }

    @Test
    func `obsolete ABA returns cannot commit or publish over latest refresh`() async throws {
        let f = RefreshFixture()
        defer { f.clean() }
        let o = owner(f)
        #expect(request(o, f, scope: "A", gate: "oldA"))
        try await waitUntil { f.pending["oldA"] != nil }
        #expect(request(o, f, scope: "B", gate: "oldB"))
        try await waitUntil { f.pending["oldB"] != nil }
        #expect(request(o, f, scope: "A", gate: "newA"))
        try await waitUntil { f.pending["newA"] != nil }
        try f.release("oldA")
        try f.release("oldB")
        await settle()
        #expect(!f.trace.contains("commit-A") && !f.trace.contains("fresh-B"))
        try f.release("newA")
        try await waitUntil { f.trace.contains("fresh-A") }
        #expect(f.trace.filter { $0 == "commit-A" }.count == 1)
        #expect(request(o, f, scope: "B"))
        try await waitUntil { f.trace.contains("fresh-B") }
    }

    @Test
    func `binding expiry rejects late writes and does not record success`() async throws {
        let f = RefreshFixture()
        defer { f.clean() }
        let o = owner(f)
        #expect(request(o, f, scope: "A", gate: "A"))
        try await waitUntil { f.pending["A"] != nil }
        f.current = false
        try f.release("A")
        await settle()
        #expect(f.trace == ["start-A"])
        f.current = true
        #expect(request(o, f, scope: "A"))
        try await waitUntil { f.trace.contains("fresh-A") }
    }

    @Test
    func `release does not retain owner while operation ignores cancellation`() async throws {
        let f = RefreshFixture()
        defer { f.clean() }
        var o: SessionMetadataRefresh<String>? = owner(f)
        weak let weakOwner = o
        #expect(try request(#require(o), f, scope: "A", gate: "A"))
        try await waitUntil { f.pending["A"] != nil }
        o = nil
        #expect(weakOwner == nil)
        try f.release("A")
        await settle()
        #expect(f.trace == ["start-A"])
    }

    @Test
    func `same binding coalesces in flight but an expired binding replaces it`() async throws {
        let f = RefreshFixture()
        defer { f.clean() }
        let o = owner(f)
        #expect(request(o, f, scope: "A", force: true, gate: "old"))
        try await waitUntil { f.pending["old"] != nil }
        #expect(!request(o, f, scope: "A"))
        #expect(f.trace == ["start-A"])
        f.current = false
        let scheduled1 = o.request(scope: "A", isCurrent: { true }, operation: { checkpoint in
            try checkpoint()
            f.trace.append("new")
        }, didRefresh: { _ in f.trace.append("fresh-new") })
        #expect(scheduled1)
        try await waitUntil { f.trace.contains("fresh-new") }
        try f.release("old")
        await settle()
        #expect(!f.trace.contains("commit-A"))
    }

    @Test
    func `bounded success inventory evicts oldest success only`() async throws {
        let f = RefreshFixture()
        defer { f.clean() }
        let o = owner(f, capacity: 2)
        for scope in ["A", "B", "C"] {
            #expect(request(o, f, scope: scope))
            try await waitUntil { f.trace.contains("fresh-" + scope) }
        }
        #expect(!request(o, f, scope: "B"))
        #expect(!request(o, f, scope: "C"))
        #expect(request(o, f, scope: "A"))
        try await waitUntil { f.trace.filter { $0 == "fresh-A" }.count == 2 }
    }

    @Test
    func `currentness probe reentry keeps the newer request`() async throws {
        let f = RefreshFixture()
        defer { f.clean() }
        let o = owner(f)
        var first = true
        let scheduled2 = !o.request(scope: "A", isCurrent: {
            if first {
                first = false
                _ = request(o, f, scope: "B")
            }
            return true
        }, operation: { _ in f.trace.append("obsolete") })
        #expect(scheduled2)
        try await waitUntil { f.trace.contains("fresh-B") }
        #expect(!f.trace.contains("obsolete"))
    }

    @Test
    func `completion clock reentry cannot mark an obsolete scope fresh`() async throws {
        let f = RefreshFixture()
        defer { f.clean() }
        let o = owner(f)
        #expect(request(o, f, scope: "A", gate: "A"))
        try await waitUntil { f.pending["A"] != nil }
        f.onClock = { [weak o] in
            f.onClock = nil
            if let o {
                _ = request(o, f, scope: "B")
            }
        }
        try f.release("A")
        try await waitUntil { f.trace.contains("fresh-B") }
        #expect(!f.trace.contains("fresh-A"))
        #expect(request(o, f, scope: "A"))
        try await waitUntil { f.trace.contains("fresh-A") }
    }

    @Test
    func `cancel cleanup reentry preserves new work`() async throws {
        let f = RefreshFixture()
        defer { f.clean() }
        let o = owner(f)
        o.request(scope: "A", isCurrent: { true }, operation: { _ in
            await withTaskCancellationHandler {
                await f.wait("A")
            } onCancel: { [weak o] in
                // This synthetic cancellation is invoked synchronously by the
                // main-actor owner below; no native callback is involved.
                MainActor.assumeIsolated {
                    if let o {
                        _ = request(o, f, scope: "B")
                    }
                }
            }
        })
        try await waitUntil { f.pending["A"] != nil }
        o.cancel()
        try await waitUntil { f.trace.contains("fresh-B") }
        try f.release("A")
        await settle()
        #expect(f.trace.filter { $0 == "fresh-B" }.count == 1)
        #expect(!request(o, f, scope: "B"))
    }

    @Test
    func `cancellation errors are quiet and invalid configuration is bounded`() async throws {
        let f = RefreshFixture()
        defer { f.clean() }
        let o = owner(f, age: .nan, capacity: 0)
        o.request(
            scope: "A",
            isCurrent: { true },
            operation: { _ in throw CancellationError() },
            didRefresh: { _ in f.trace.append("fresh") },
            didFail: { _ in f.trace.append("failed") }
        )
        await settle()
        #expect(f.trace.isEmpty)
        #expect(request(o, f, scope: "A"))
        try await waitUntil { f.trace.contains("fresh-A") }
        f.date = Date(timeIntervalSince1970: 1001)
        #expect(!request(o, f, scope: "A"))
        #expect(request(o, f, scope: "B"))
        try await waitUntil { f.trace.contains("fresh-B") }
        #expect(request(o, f, scope: "A"))
        try await waitUntil { f.trace.filter { $0 == "fresh-A" }.count == 2 }
    }

    @Test
    func `a failure after binding expiry is quiet and leaves no phantom in flight work`() async throws {
        let f = RefreshFixture()
        defer { f.clean() }
        let o = owner(f)
        o.request(scope: "A", isCurrent: { f.current }, operation: { _ in
            await f.wait("A")
            throw Failure.expected
        }, didRefresh: { _ in f.trace.append("obsolete-fresh") }, didFail: { _ in f.trace.append("obsolete-failure") })
        try await waitUntil { f.pending["A"] != nil }
        f.current = false
        try f.release("A")
        await settle()
        #expect(f.trace.isEmpty)
        f.current = true
        #expect(request(o, f, scope: "A"))
        try await waitUntil { f.trace.contains("fresh-A") }
    }

    @Test
    func `coalescing binding probe reentry cannot override newer work`() async throws {
        let f = RefreshFixture()
        defer { f.clean() }
        let o = owner(f)
        var probe = false
        o.request(scope: "A", isCurrent: {
            if probe {
                probe = false
                _ = request(o, f, scope: "B")
            }
            return true
        }, operation: { checkpoint in
            await f.wait("oldA")
            try checkpoint()
            f.trace.append("obsolete-commit")
        })
        try await waitUntil { f.pending["oldA"] != nil }
        probe = true
        #expect(!request(o, f, scope: "A"))
        try await waitUntil { f.trace.contains("fresh-B") }
        try f.release("oldA")
        await settle()
        #expect(!f.trace.contains("obsolete-commit"))
        #expect(!f.trace.contains("fresh-A"))
    }
}
