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
@testable import SwiftfinAsyncStreams
import Testing

private final class DeliveryQueue: Sendable {
    private let entries = OSAllocatedUnfairLock(initialState: [@MainActor @Sendable () -> Void]())
    func append(_ action: @escaping @MainActor @Sendable () -> Void) {
        entries.withLock { $0.append(action) }
    }

    @MainActor
    func drain() {
        let actions = entries.withLock { entries in
            let actions = entries
            entries.removeAll()
            return actions
        }
        actions.forEach { $0() }
    }
}

@MainActor
private final class StreamSource {
    private let subject = PassthroughSubject<Int, Never>()
    private let counts = OSAllocatedUnfairLock(initialState: (starts: 0, stops: 0))
    var starts: Int {
        counts.withLock { $0.starts }
    }

    var stops: Int {
        counts.withLock { $0.stops }
    }

    func publisher() -> AnyPublisher<Int, Never> {
        subject.handleEvents(
            receiveSubscription: { [counts] _ in counts.withLock { $0.starts += 1 } },
            receiveCancel: { [counts] in counts.withLock { $0.stops += 1 } }
        ).eraseToAnyPublisher()
    }

    func send(_ value: Int) {
        subject.send(value)
    }
}

@MainActor
private final class StreamPresentation {
    var values: [Int] = []
}

@Suite(.serialized) @MainActor
struct ScopedPublisherContracts {
    private func owner(_ queue: DeliveryQueue) -> ScopedPublisher<String, Int> {
        .init(schedule: queue.append)
    }

    @Test
    func `logout retires source and drops already queued values`() {
        let queue = DeliveryQueue(), source = StreamSource(), presentation = StreamPresentation()
        let lease = owner(queue)
        lease.replace(scope: "account-A", makePublisher: source.publisher, isCurrent: { true }) { presentation.values.append($0) }
        source.send(1)
        lease.cancel()
        source.send(2)
        queue.drain()
        #expect(source.starts == 1 && source.stops == 1)
        #expect(presentation.values.isEmpty)
    }

    @Test
    func `root and connection replacements reject obsolete delivery and stop sources`() {
        let queue = DeliveryQueue(), a = StreamSource(), b = StreamSource(), c = StreamSource(), p = StreamPresentation()
        let lease = owner(queue)
        lease.replace(scope: "A/transport1", makePublisher: a.publisher, isCurrent: { true }) { p.values.append($0) }
        a.send(1)
        lease.replace(scope: "B/transport1", makePublisher: b.publisher, isCurrent: { true }) { p.values.append($0) }
        b.send(2)
        lease.replace(scope: "B/transport2", makePublisher: c.publisher, isCurrent: { true }) { p.values.append($0) }
        c.send(3)
        queue.drain()
        #expect(p.values == [3])
        #expect(a.stops == 1 && b.stops == 1 && c.starts == 1 && c.stops == 0)
    }

    @Test
    func `same identity reuses subscription and latest presentation hook`() {
        let queue = DeliveryQueue(), a = StreamSource(), unused = StreamSource(), p = StreamPresentation()
        let lease = owner(queue)
        #expect(lease.replace(scope: "A", makePublisher: a.publisher, isCurrent: { true }) { p.values.append($0) })
        a.send(1)
        #expect(!lease.replace(scope: "A", makePublisher: unused.publisher, isCurrent: { true }) { p.values.append($0 * 10) })
        queue.drain()
        #expect(p.values == [10] && a.starts == 1 && a.stops == 0 && unused.starts == 0)
    }

    @Test
    func `returning to the same account never admits its old generation`() {
        let queue = DeliveryQueue(), a = StreamSource(), b = StreamSource(), p = StreamPresentation()
        let lease = owner(queue)
        lease.replace(scope: "A", makePublisher: a.publisher, isCurrent: { true }) { p.values.append($0) }
        a.send(1)
        lease.replace(scope: "B", makePublisher: b.publisher, isCurrent: { true }) { p.values.append($0) }
        b.send(2)
        lease.replace(scope: "A", makePublisher: a.publisher, isCurrent: { true }) { p.values.append($0) }
        a.send(3)
        queue.drain()
        #expect(p.values == [3] && a.starts == 2 && a.stops == 1 && b.stops == 1)
    }

    @Test
    func `expired binding drops pending value and retires its subscription`() {
        let queue = DeliveryQueue(), a = StreamSource(), p = StreamPresentation()
        let lease = owner(queue)
        lease.replace(scope: "A", makePublisher: a.publisher, isCurrent: { false }) { p.values.append($0) }
        a.send(1)
        queue.drain()
        #expect(p.values.isEmpty && a.stops == 1)
    }

    @Test
    func `currentness reentry cannot publish or cancel a newer binding`() {
        let queue = DeliveryQueue(), a = StreamSource(), b = StreamSource(), p = StreamPresentation()
        let lease = owner(queue)
        lease.replace(scope: "A", makePublisher: a.publisher, isCurrent: {
            lease.replace(scope: "B", makePublisher: b.publisher, isCurrent: { true }) { p.values.append($0) }
            return false
        }) { p.values.append($0) }
        a.send(1)
        queue.drain()
        b.send(2)
        queue.drain()
        #expect(p.values == [2] && a.stops == 1 && b.stops == 0)
        lease.cancel()
    }

    @Test
    func `retirement cleanup reentry preserves its newly installed source`() {
        let queue = DeliveryQueue(), a = StreamSource(), b = StreamSource(), unused = StreamSource(), p = StreamPresentation()
        let lease = owner(queue)
        lease.replace(scope: "A", makePublisher: {
            a.publisher().handleEvents(receiveCancel: { [weak lease] in
                MainActor.assumeIsolated {
                    _ = lease?.replace(scope: "B", makePublisher: b.publisher, isCurrent: { true }) { p.values.append($0) }
                }
            }).eraseToAnyPublisher()
        }, isCurrent: { true }) { p.values.append($0) }
        a.send(1)
        #expect(!lease.replace(scope: "unused", makePublisher: unused.publisher, isCurrent: { true }) { p.values.append($0) })
        b.send(2)
        queue.drain()
        #expect(p.values == [2] && a.stops == 1 && b.starts == 1 && unused.starts == 0)
        lease.cancel()
    }

    @Test
    func `factory reentry never subscribes to the superseded source`() {
        let queue = DeliveryQueue(), a = StreamSource(), b = StreamSource(), p = StreamPresentation()
        let lease = owner(queue)
        #expect(!lease.replace(scope: "A", makePublisher: {
            lease.replace(scope: "B", makePublisher: b.publisher, isCurrent: { true }) { p.values.append($0) }
            return a.publisher()
        }, isCurrent: { true }) { p.values.append($0) })
        b.send(2)
        queue.drain()
        #expect(p.values == [2] && a.starts == 0 && b.starts == 1)
    }

    @Test
    func `subscription reentry cancels only the superseded candidate`() {
        let queue = DeliveryQueue(), a = StreamSource(), b = StreamSource(), p = StreamPresentation()
        let lease = owner(queue)
        #expect(!lease.replace(scope: "A", makePublisher: {
            a.publisher().handleEvents(receiveSubscription: { [weak lease] _ in
                MainActor.assumeIsolated {
                    _ = lease?.replace(scope: "B", makePublisher: b.publisher, isCurrent: { true }) { p.values.append($0) }
                }
            }).eraseToAnyPublisher()
        }, isCurrent: { true }) { p.values.append($0) })
        a.send(1)
        b.send(2)
        queue.drain()
        #expect(p.values == [2] && a.stops == 1 && b.stops == 0)
    }

    @Test
    func `dropping the owner cancels source and pending receipts do not retain it`() {
        let queue = DeliveryQueue(), a = StreamSource(), p = StreamPresentation()
        var lease: ScopedPublisher<String, Int>? = owner(queue)
        weak let weakLease = lease
        lease?.replace(scope: "A", makePublisher: a.publisher, isCurrent: { true }) { p.values.append($0) }
        a.send(1)
        lease = nil
        queue.drain()
        #expect(weakLease == nil && a.stops == 1 && p.values.isEmpty)
    }

    @Test
    func `weak UI receipt releases presentation without cancelling another owner`() {
        let queue = DeliveryQueue(), a = StreamSource()
        var p: StreamPresentation? = StreamPresentation()
        weak let weakPresentation = p
        let lease = owner(queue)
        lease.replace(scope: "A", makePublisher: a.publisher, isCurrent: { true }) { [weak p] value in p?.values.append(value) }
        a.send(1)
        p = nil
        queue.drain()
        #expect(weakPresentation == nil && a.stops == 0)
    }

    @Test
    func `foreign executor emissions enter the main actor through the production scheduler`() async throws {
        let p = StreamPresentation()
        let lease = ScopedPublisher<String, Int>()
        lease.replace(scope: "A", makePublisher: {
            Just(7).subscribe(on: DispatchQueue.global()).eraseToAnyPublisher()
        }, isCurrent: { true }) { value in
            MainActor.preconditionIsolated()
            p.values.append(value)
        }
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while p.values.isEmpty {
            try #require(ContinuousClock.now < deadline)
            await Task.yield()
        }
        #expect(p.values == [7])
        lease.cancel()
    }
}
