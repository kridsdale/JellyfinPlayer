//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation
import SwiftfinPaging
import Testing

private struct Row: Identifiable, Equatable { let id: Int
    var name: String = ""
}

private enum Failure: Error { case unavailable }
@MainActor
private final class Flag { var value: Bool
    init(_ value: Bool) {
        self.value = value
    }
}

@MainActor
private final class Clock { var value: Duration = .seconds(10) }
@MainActor
private final class WeakOwner<T: AnyObject> { weak var value: T?
    init(_ value: T?) {
        self.value = value
    }
}

@MainActor
private final class Gate<Value: Sendable> {
    var waiters: [CheckedContinuation<Value, any Error>] = []
    func wait() async throws -> Value {
        try await withCheckedThrowingContinuation { waiters.append($0) }
    }

    func fail(_ error: Failure) {
        waiters.removeFirst().resume(throwing: error)
    }

    func succeed(_ value: Value) {
        waiters.removeFirst().resume(returning: value)
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

@MainActor
private func canceled(_ task: Task<Void, any Error>) async {
    do { try await task.value
        Issue.record("An obsolete request published successfully")
    } catch is CancellationError {}
    catch { Issue.record("Unexpected error: \(error)") }
}

@Suite("Pagination ownership")
@MainActor
struct PagingStoreTests {
    @Test
    func `consumed cursor survives overlap filtering and deletion`() async throws {
        let store = PagingStore<Row>(pageSize: 3)
        var requests: [PagingRequest] = []
        let source = PagingSource<Row>(identity: UUID(), isCurrent: { true }, load: { request in
            requests.append(request)
            switch request.offset {
            case 0: return PagingPage(items: [Row(id: 1), Row(id: 2)], consumedCount: 3)
            case 3: return PagingPage(items: [Row(id: 2), Row(id: 3), Row(id: 4)])
            default: return PagingPage(items: [Row(id: 5)])
            }
        })
        try await store.refresh(using: source)
        store.remove { $0.id == 1 }
        try await store.nextPage(using: source)
        #expect(store.elements.map(\.id) == [2, 3, 4])
        try await store.nextPage(using: source)
        try await store.nextPage(using: source)
        #expect(requests.map(\.offset) == [0, 3, 6])
        #expect(store.elements.map(\.id) == [2, 3, 4, 5])
        #expect(!store.hasMore)
    }

    @Test
    func `non paged library loads once even when full`() async throws {
        let store = PagingStore<Row>(pageSize: 1)
        var count = 0
        let source = PagingSource<Row>(identity: UUID(), canPage: false, isCurrent: { true }, load: { _ in
            count += 1
            return PagingPage(items: [Row(id: 1), Row(id: 2)])
        })
        try await store.refresh(using: source)
        try await store.nextPage(using: source)
        #expect(count == 1)
        #expect(!store.hasMore)
    }

    @Test
    func `failed next page can retry the same cursor`() async throws {
        let store = PagingStore<Row>(pageSize: 1)
        var requests: [Int] = []
        var failed = false
        let source = PagingSource<Row>(identity: UUID(), isCurrent: { true }, load: { request in
            requests.append(request.offset)
            if request.offset == 1 && !failed {
                failed = true
                throw Failure.unavailable
            }
            return PagingPage(items: [Row(id: request.offset)])
        })
        try await store.refresh(using: source)
        do { try await store.nextPage(using: source)
            Issue.record("Missing transport error")
        } catch Failure.unavailable {}
        try await store.nextPage(using: source)
        #expect(requests == [0, 1, 1])
        #expect(store.elements.map(\.id) == [0, 1])
    }

    @Test
    func `failed background refresh preserves content and committed cursor`() async throws {
        let store = PagingStore<Row>(pageSize: 1)
        var requests: [Int] = []
        let fail = Flag(false)
        let source = PagingSource<Row>(identity: UUID(), isCurrent: { true }, load: { request in
            requests.append(request.offset)
            if fail.value {
                throw Failure.unavailable
            }
            return PagingPage(items: [Row(id: request.offset)])
        })
        try await store.refresh(using: source)
        try await store.nextPage(using: source)
        fail.value = true
        do { try await store.refresh(using: source, retainingContent: true)
            Issue.record("Missing error")
        } catch Failure.unavailable {}
        #expect(store.elements.map(\.id) == [0, 1])
        fail.value = false
        try await store.nextPage(using: source)
        #expect(requests == [0, 1, 0, 2])
    }

    @Test
    func `superseded refresh cannot overwrite or clear its replacement`() async throws {
        let store = PagingStore<Row>(pageSize: 1)
        let gate = Gate<PagingPage<Row>>()
        var first = true
        let source = PagingSource<Row>(identity: UUID(), isCurrent: { true }, load: { _ in
            if first {
                first = false
                return try await gate.wait()
            }
            return PagingPage(items: [Row(id: 2)])
        })
        let old = Task { try await store.refresh(using: source) }
        await settle { gate.waiters.count == 1 }
        try await store.refresh(using: source)
        gate.succeed(PagingPage(items: [Row(id: 1)]))
        await canceled(old)
        #expect(store.elements.map(\.id) == [2])
    }

    @Test
    func `overlapping next page calls load only once`() async throws {
        let store = PagingStore<Row>(pageSize: 1)
        let gate = Gate<PagingPage<Row>>()
        var count = 0
        let source = PagingSource<Row>(identity: UUID(), isCurrent: { true }, load: { _ in
            count += 1
            return try await gate.wait()
        })
        let flight = Task { try await store.nextPage(using: source) }
        await settle { gate.waiters.count == 1 }
        try await store.nextPage(using: source)
        #expect(count == 1)
        gate.succeed(PagingPage(items: [Row(id: 1)]))
        try await flight.value
    }

    @Test
    func `old account cannot erase the new account`() async throws {
        let store = PagingStore<Row>(pageSize: 1)
        let gate = Gate<PagingPage<Row>>()
        let valid = Flag(true)
        let oldSource = PagingSource<Row>(identity: UUID(), isCurrent: { valid.value }, load: { _ in try await gate.wait() })
        let newSource = PagingSource<Row>(identity: UUID(), isCurrent: { true }, load: { _ in PagingPage(items: [Row(id: 8)]) })
        let old = Task { try await store.refresh(using: oldSource) }
        await settle { gate.waiters.count == 1 }
        valid.value = false
        try await store.refresh(using: newSource)
        gate.succeed(PagingPage(items: [Row(id: 1)]))
        await canceled(old)
        do { try await store.nextPage(using: oldSource)
            Issue.record("Old account was accepted")
        } catch is CancellationError {}
        #expect(store.elements.map(\.id) == [8])
    }

    @Test
    func `invalid current binding clears previously published content`() async throws {
        let store = PagingStore<Row>(pageSize: 1)
        let valid = Flag(true)
        let source = PagingSource<Row>(identity: UUID(), isCurrent: { valid.value }, load: { _ in PagingPage(items: [Row(id: 1)]) })
        try await store.refresh(using: source)
        valid.value = false
        do { try await store.nextPage(using: source)
            Issue.record("Invalid binding was accepted")
        } catch is CancellationError {}
        #expect(store.elements.isEmpty)
    }

    @Test
    func `cancellation after non cooperating load does not publish`() async {
        let store = PagingStore<Row>()
        let gate = Gate<PagingPage<Row>>()
        let source = PagingSource<Row>(identity: UUID(), isCurrent: { true }, load: { _ in try await gate.wait() })
        let task = Task { try await store.refresh(using: source) }
        await settle { gate.waiters.count == 1 }
        task.cancel()
        gate.succeed(PagingPage(items: [Row(id: 1)]))
        await canceled(task)
        #expect(store.elements.isEmpty)
    }

    @Test
    func `search edit revokes old results before debounce including ABA`() async {
        let store = PagingStore<Row>(pageSize: 1)
        let gate = Gate<PagingPage<Row>>()
        let source = PagingSource<Row>(
            identity: UUID(),
            isCurrent: { true },
            load: { _ in PagingPage(items: []) },
            search: { _ in try await gate.wait() }
        )
        let task = Task { try await store.search("first", using: source) }
        await settle { gate.waiters.count == 1 }
        store.prepareSearch("second")
        store.prepareSearch("first")
        gate.succeed(PagingPage(items: [Row(id: 1)]))
        await canceled(task)
        #expect(store.searchElements.isEmpty)
        #expect(!store.hasMoreSearch)
    }

    @Test
    func `search and browse have independent consumed cursors and updates`() async throws {
        let store = PagingStore<Row>(pageSize: 2)
        var requests: [PagingRequest] = []
        let source = PagingSource<Row>(identity: UUID(), isCurrent: { true }, load: { request in
            requests.append(request)
            return PagingPage(items: [Row(id: request.offset + 10)], consumedCount: 2)
        }, search: { request in
            requests.append(request)
            return PagingPage(items: [Row(id: request.offset + 10)], consumedCount: 2)
        })
        try await store.refresh(using: source)
        try await store.search(" query ", using: source)
        try await store.nextPage(using: source)
        try await store.nextSearchPage(using: source)
        #expect(requests.map(\.offset) == [0, 0, 2, 2])
        #expect(requests.map(\.query) == [nil, "query", nil, "query"])
        store.update { var row = $0
            row.name = "updated"
            return row
        }
        #expect(store.elements.allSatisfy { $0.name == "updated" })
        #expect(store.searchElements.allSatisfy { $0.name == "updated" })
        store.remove { $0.id == 10 }
        #expect(store.elements.map(\.id) == [12])
        #expect(store.searchElements.map(\.id) == [12])
        try await store.search("   ", using: source)
        #expect(store.searchElements.isEmpty)
        #expect(!store.hasMoreSearch)
    }

    @Test
    func `search pages coalesce and respect non paged sources`() async throws {
        let store = PagingStore<Row>(pageSize: 1)
        let gate = Gate<PagingPage<Row>>()
        var count = 0
        let source = PagingSource<Row>(
            identity: UUID(),
            canPage: false,
            isCurrent: { true },
            load: { _ in PagingPage(items: []) },
            search: { _ in
                count += 1
                return try await gate.wait()
            }
        )
        let first = Task { try await store.search("query", using: source) }
        await settle { gate.waiters.count == 1 }
        try await store.nextSearchPage(using: source)
        gate.succeed(PagingPage(items: [Row(id: 1)]))
        try await first.value
        try await store.nextSearchPage(using: source)
        #expect(count == 1)
        #expect(!store.hasMoreSearch)
    }

    @Test
    func `random result is revoked on binding replacement`() async {
        let store = PagingStore<Row>()
        let gate = Gate<Row?>()
        let source = PagingSource<Row>(
            identity: UUID(),
            isCurrent: { true },
            load: { _ in PagingPage(items: []) },
            random: { try await gate.wait() }
        )
        let task = Task { _ = try await store.randomElement(using: source) }
        await settle { gate.waiters.count == 1 }
        store.invalidate()
        gate.succeed(Row(id: 1))
        await canceled(task)
    }

    @Test
    func `random fallback uses only published rows`() async throws {
        let store = PagingStore<Row>()
        let source = PagingSource<Row>(identity: UUID(), isCurrent: { true }, load: { _ in PagingPage(items: [Row(id: 1)]) })
        try await store.refresh(using: source)
        #expect(try await store.randomElement(using: source)?.id == 1)
        store.remove { _ in true }
        #expect(try await store.randomElement(using: source) == nil)
    }

    @Test
    func `cursor overflow is an error without publishing the page`() async throws {
        let store = PagingStore<Row>(pageSize: 1)
        let source = PagingSource<Row>(identity: UUID(), isCurrent: { true }, load: { request in
            PagingPage(items: [Row(id: request.offset)], consumedCount: Int.max)
        })
        try await store.refresh(using: source)
        do { try await store.nextPage(using: source)
            Issue.record("Cursor overflow was accepted")
        } catch PagingError.cursorOverflow {}
        #expect(store.elements.map(\.id) == [0])
    }

    @Test(arguments: ["browse", "search", "random"])
    func `obsolete transport failure is cancellation`(_ operation: String) async throws {
        let store = PagingStore<Row>(pageSize: 1)
        let gate = Gate<PagingPage<Row>>()
        let source = PagingSource<Row>(
            identity: UUID(),
            isCurrent: { true },
            load: { _ in try await gate.wait() },
            search: { _ in try await gate.wait() },
            random: { try await (gate.wait()).items.first }
        )
        let old = Task {
            switch operation {
            case "browse": try await store.refresh(using: source)
            case "search": try await store.search("query", using: source)
            default: _ = try await store.randomElement(using: source)
            }
        }
        await settle { gate.waiters.count == 1 }
        let replacement = PagingSource<Row>(identity: UUID(), isCurrent: { true }, load: { _ in PagingPage(items: [Row(id: 8)]) })
        try await store.refresh(using: replacement)
        gate.fail(.unavailable)
        await canceled(old)
        #expect(store.elements.map(\.id) == [8])
    }

    @Test
    func `request description redacts search text`() {
        let request = PagingRequest(offset: 2, limit: 3, query: "private query")
        #expect(!String(describing: request).contains("private query"))
        #expect(!String(reflecting: request).contains("private query"))
        #expect(PagingStore<Row>(pageSize: 0).pageSize == 1)
        #expect(PagingPage<Row>(items: [Row(id: 1)], consumedCount: -1).consumedCount == 1)
    }
}

@Suite("Refresh scheduling ownership")
@MainActor
struct PagingSchedulerTests {
    @Test
    func `newest debounced refresh wins and cancellation is final`() async {
        let gate = Gate<Void>()
        let scheduler = PagingRefreshScheduler(sleep: { _ in try await gate.wait() })
        var delivered: [Int] = []
        scheduler.schedule { delivered.append(1) }
        await settle { gate.waiters.count == 1 }
        scheduler.schedule { delivered.append(2) }
        await settle { gate.waiters.count == 2 }
        gate.succeed(())
        gate.succeed(())
        await settle { delivered == [2] }
        scheduler.schedule(minimumInterval: .zero) { delivered.append(3) }
        await settle { gate.waiters.count == 1 }
        scheduler.cancel()
        gate.succeed(())
        for _ in 0 ..< 20 {
            await Task.yield()
        }
        #expect(delivered == [2])
    }

    @Test
    func `throttle starts at successful completion using monotonic time`() async {
        let clock = Clock()
        let scheduler = PagingRefreshScheduler(now: { clock.value }, sleep: { _ in })
        var count = 0
        #expect(scheduler.schedule(debounce: .zero) { count += 1 })
        await settle { count == 1 }
        clock.value = .seconds(14)
        #expect(!scheduler.schedule(debounce: .zero) { count += 1 })
        clock.value = .seconds(15)
        #expect(scheduler.schedule(debounce: .zero) { count += 1 })
        await settle { count == 2 }
    }

    @Test
    func `pending delay does not retain its owner`() async {
        let gate = Gate<Void>()
        var scheduler: PagingRefreshScheduler? = PagingRefreshScheduler(sleep: { _ in try await gate.wait() })
        let owner = WeakOwner(scheduler)
        var delivered = false
        scheduler?.schedule { delivered = true }
        await settle { gate.waiters.count == 1 }
        scheduler = nil
        #expect(owner.value == nil)
        gate.succeed(())
        for _ in 0 ..< 20 {
            await Task.yield()
        }
        #expect(!delivered)
    }
}
