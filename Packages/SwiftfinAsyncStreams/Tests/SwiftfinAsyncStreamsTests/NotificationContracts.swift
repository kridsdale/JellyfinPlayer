//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Combine
import Foundation
import os
import SwiftfinAsyncStreams
import Testing

private final class NotificationTrace: Sendable {
    private let storage = OSAllocatedUnfairLock(initialState: [String]())
    func append(_ value: String) {
        storage.withLock { $0.append(value) }
    }

    var values: [String] {
        storage.withLock { $0 }
    }
}

// Raw callback creation is outside any actor so foreign posting has no inferred
// executor assertion. Only checked-Sendable values reach the locked collector.
private func record(_ publisher: AnyPublisher<some Sendable, Never>, in trace: NotificationTrace) -> AnyCancellable {
    publisher.sink { trace.append(String(describing: $0)) }
}

@MainActor
private final class NotificationReader {
    var value = false
    var reads = 0
    func read() -> Bool {
        MainActor.preconditionIsolated()
        reads += 1
        return value
    }
}

@Suite(.serialized) @MainActor
struct NotificationContracts {
    private func event<Value: Sendable>(_ type: Value.Type = Value.self) -> NotificationEvent<Value> {
        .init(.init("synthetic-event"))
    }

    private func settle(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while !condition() {
            try #require(ContinuousClock.now < deadline)
            await Task.yield()
        }
    }

    private func drainMainQueue() async {
        await withCheckedContinuation { continuation in DispatchQueue.main.async { continuation.resume() } }
    }

    @Test
    func `raw typed delivery is synchronous and rejects wrong absent foreign center and name`() {
        let center = NotificationCenter()
        let trace = NotificationTrace()
        let key = event(Int.self)
        let token = record(key.publisher(in: center), in: trace)
        key.post(3, to: center)
        #expect(trace.values == ["3"])
        center.post(name: key.name, object: nil, userInfo: ["payload": "wrong"])
        center.post(name: key.name, object: nil)
        NotificationCenter().post(name: key.name, object: nil, userInfo: ["payload": 99])
        center.post(name: .init("other-event"), object: nil, userInfo: ["payload": 99])
        #expect(trace.values == ["3"])
        token.cancel()
        key.post(4, to: center)
        #expect(trace.values == ["3"])
    }

    @Test
    func `void events ignore decoder and preserve nil userInfo for no argument posts`() {
        let center = NotificationCenter()
        let trace = NotificationTrace()
        let info = NotificationTrace()
        let key = NotificationEvent<Void>(.init("void")) { _ in trace.append("decoder")
            return nil
        }
        let token = record(key.publisher(in: center), in: trace)
        let observer = center.publisher(for: key.name).sink { info.append($0.userInfo == nil ? "nil" : "payload") }
        key.post(to: center)
        key.post((), to: center)
        center.post(name: key.name, object: nil, userInfo: ["other": "value"])
        #expect(trace.values == ["()", "()", "()"])
        #expect(info.values == ["nil", "payload", "payload"])
        token.cancel()
        observer.cancel()
    }

    @Test
    func `custom raw decoder receives only actual userInfo and may discard payload shape`() {
        let center = NotificationCenter()
        let trace = NotificationTrace()
        let key = NotificationEvent<Int>(.init("custom")) { $0["number"] as? Int }
        let token = record(key.publisher(in: center), in: trace)
        key.post(999, to: center)
        center.post(name: key.name, object: nil, userInfo: ["number": 7])
        center.post(name: key.name, object: nil, userInfo: ["number": "wrong"])
        center.post(name: key.name, object: nil)
        #expect(trace.values == ["7"])
        token.cancel()
    }

    @Test
    func `subscriptions are lazy nonreplaying and cancellation affects only its subscriber`() {
        let center = NotificationCenter()
        let first = NotificationTrace()
        let second = NotificationTrace()
        let key = event(Int.self)
        let publisher = key.publisher(in: center)
        key.post(0, to: center)
        let a = record(publisher, in: first)
        let b = record(publisher, in: second)
        key.post(1, to: center)
        a.cancel()
        key.post(2, to: center)
        #expect(first.values == ["1"] && second.values == ["1", "2"])
        b.cancel()
        let c = record(publisher, in: first)
        key.post(3, to: center)
        #expect(first.values == ["1", "3"])
        c.cancel()
    }

    @Test
    func `same immutable descriptor keeps independent injected center subscriptions`() {
        let a = NotificationCenter()
        let b = NotificationCenter()
        let first = NotificationTrace()
        let second = NotificationTrace()
        let key = event(Int.self)
        let x = record(key.publisher(in: a), in: first)
        let y = record(key.publisher(in: b), in: second)
        key.post(1, to: a)
        key.post(2, to: b)
        #expect(first.values == ["1"] && second.values == ["2"])
        x.cancel()
        y.cancel()
    }

    @Test
    func `foreign raw posting retains synchronous ordering with Sendable snapshots`() async {
        let center = NotificationCenter()
        let trace = NotificationTrace()
        let key = event(Int.self)
        let token = record(key.publisher(in: center), in: trace)
        await Task.detached { key.post(7, to: center)
            trace.append("after")
        }.value
        #expect(trace.values == ["7", "after"])
        token.cancel()
    }

    @Test
    func `main actor reader handles userInfo free foreign signals and reads delivery time state`() async throws {
        let center = NotificationCenter()
        let trace = NotificationTrace()
        let key = event(Bool.self)
        let reader = NotificationReader()
        let token = record(key.mainActorPublisher(in: center, read: { reader.read() }), in: trace)
        center.post(name: key.name, object: nil)
        #expect(reader.reads == 0)
        reader.value = true
        try await settle { trace.values == ["true"] }
        await Task.detached { center.post(name: key.name, object: nil, userInfo: ["ignored": "value"]) }.value
        try await settle { reader.reads == 2 }
        #expect(trace.values == ["true", "true"])
        token.cancel()
    }

    @Test
    func `cancel before queued actor delivery prevents status reads and values`() async {
        let center = NotificationCenter()
        let trace = NotificationTrace()
        let key = event(Bool.self)
        let reader = NotificationReader()
        let token = record(key.mainActorPublisher(in: center, read: { reader.read() }), in: trace)
        center.post(name: key.name, object: nil)
        token.cancel()
        await drainMainQueue()
        #expect(reader.reads == 0 && trace.values.isEmpty)
    }

    @Test
    func `weak platform reader can retire while a notification subscription remains`() async {
        let center = NotificationCenter()
        let trace = NotificationTrace()
        let key = event(Bool.self)
        var reader: NotificationReader? = NotificationReader()
        let isRetired = { [weak reader] in reader == nil }
        let token = record(key.mainActorPublisher(in: center, read: { [weak reader] in reader?.read() }), in: trace)
        reader = nil
        #expect(isRetired())
        center.post(name: key.name, object: nil)
        await drainMainQueue()
        #expect(trace.values.isEmpty)
        token.cancel()
    }
}
