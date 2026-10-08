//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation
import JellyfinAPI
@testable import SwiftfinNetworking
import Testing

@MainActor
private final class Lease: SocketSubscriptionLease {
    let topic: JellyfinSocket.Subscription
    let delay: Duration
    let interval: Duration
    var cancelled = false
    init(topic: JellyfinSocket.Subscription, delay: Duration, interval: Duration) {
        self.topic = topic
        self.delay = delay
        self.interval = interval
    }

    func cancel() {
        cancelled = true
    }
}

@MainActor
private final class Driver: SocketSessionDriver {
    let events: AsyncThrowingStream<JellyfinSocket.Session.Event, any Error>
    let continuation: AsyncThrowingStream<JellyfinSocket.Session.Event, any Error>.Continuation
    var leases: [Lease] = []
    var disconnects = 0
    var finishOnDisconnect = true
    var onSubscribe: (@MainActor () -> Void)?
    var onDisconnect: (@MainActor () -> Void)?
    init() {
        (events, continuation) = AsyncThrowingStream.makeStream()
    }

    func subscribe(_ topic: JellyfinSocket.Subscription, delay: Duration, interval: Duration) -> any SocketSubscriptionLease {
        let lease = Lease(topic: topic, delay: delay, interval: interval)
        leases.append(lease)
        let action = onSubscribe
        onSubscribe = nil
        action?()
        return lease
    }

    func disconnect() {
        disconnects += 1
        let action = onDisconnect
        onDisconnect = nil
        action?()
        if finishOnDisconnect {
            continuation.finish()
        }
    }

    func connected() {
        continuation.yield(.connected(URL(string: "https://unit.example.test/socket")!))
    }
}

@MainActor
private final class Factory {
    let drivers: [Driver]
    var requests = 0
    var onNext: (@MainActor () -> Void)?
    init(_ drivers: [Driver]) {
        self.drivers = drivers
    }

    func next() -> (any SocketSessionDriver)? {
        guard requests < drivers.count else { return nil }
        let driver = drivers[requests]
        requests += 1
        let action = onNext
        onNext = nil
        action?()
        return driver
    }
}

@Suite(.serialized) @MainActor
struct SocketContracts {
    private func until(_ condition: @MainActor () -> Bool) async {
        for _ in 0 ..< 200 where !condition() {
            await Task.yield()
        }
    }

    @Test
    func `scoped subscriptions retain cadence and payload topics cannot cross streams`() async {
        let driver = Driver()
        let factory = Factory([driver])
        let controller = JellyfinSocketController(sessionFactory: { factory.next() })
        let sessions = controller.sessions(delay: .seconds(1), interval: .seconds(3))
        let activities = controller.activityLog()
        var received: [[SessionInfoDto]] = []
        let consumer = Task { for await value in sessions {
            received.append(value)
        } }
        let other = Task { for await _ in activities {} }
        controller.start()
        await until { factory.requests == 1 }
        #expect(driver.leases.contains { $0.topic == .sessions && $0.delay == .seconds(1) && $0.interval == .seconds(3) })
        driver.continuation.yield(.message(.activityLogEntryMessage(.init(data: []))))
        driver.continuation.yield(.message(.sessionsMessage(.init(data: [.init(id: "synthetic-session")]))))
        await until { !received.isEmpty }
        #expect(received.count == 1 && received.first?.first?.id == "synthetic-session")
        consumer.cancel()
        other.cancel()
        controller.stop()
    }

    @Test
    func `background consumer cancellation releases only its own native claim`() async {
        let driver = Driver()
        let factory = Factory([driver])
        let controller = JellyfinSocketController(sessionFactory: { factory.next() })
        let first = controller.sessions()
        let second = controller.activityLog()
        let consumer = Task { for await _ in first {} }
        let retained = Task { for await _ in second {} }
        controller.start()
        await until { driver.leases.count == 2 }
        await Task.detached { consumer.cancel() }.value
        await until { driver.leases.first(where: { $0.topic == .sessions })?.cancelled == true }
        #expect(driver.leases.first(where: { $0.topic == .sessions })?.cancelled == true)
        #expect(driver.leases.first(where: { $0.topic == .activityLog })?.cancelled == false)
        retained.cancel()
        controller.stop()
    }

    @Test
    func `restart ignores old session cleanup and preserves new connected state`() async {
        let old = Driver()
        old.finishOnDisconnect = false
        let new = Driver()
        let factory = Factory([old, new])
        let controller = JellyfinSocketController(sessionFactory: { factory.next() })
        var states: [Bool] = []
        let values = controller.connectionStates()
        let consumer = Task { for await value in values {
            states.append(value)
        } }
        controller.start()
        await until { factory.requests == 1 }
        controller.start()
        await until { factory.requests == 2 }
        new.connected()
        await until { states.last == true }
        old.continuation.finish()
        await Task.yield()
        #expect(states.last == true && new.disconnects == 0)
        consumer.cancel()
        controller.stop()
    }

    @Test
    func `authorization refusal waits for a new signal instead of retrying claims`() async {
        let first = Driver()
        let second = Driver()
        let factory = Factory([first, second])
        var backoffs = 0
        let controller = JellyfinSocketController(sessionFactory: { factory.next() }, backoff: { backoffs += 1 })
        let values = controller.sessions()
        let consumer = Task { for await _ in values {} }
        controller.start()
        await until { factory.requests == 1 }
        first.continuation.finish(throwing: JellyfinSocket.Session.SocketError.unauthorized(statusCode: 401))
        for _ in 0 ..< 20 {
            await Task.yield()
        }
        #expect(factory.requests == 1 && backoffs == 0)
        let signal = controller.activityLog()
        let other = Task { for await _ in signal {} }
        await until { factory.requests == 2 }
        #expect(factory.requests == 2)
        consumer.cancel()
        other.cancel()
        controller.stop()
    }

    @Test
    func `lost connection with claims uses backoff and reapplies scoped subscriptions`() async {
        let first = Driver()
        let second = Driver()
        let factory = Factory([first, second])
        var backoffs = 0
        let controller = JellyfinSocketController(sessionFactory: { factory.next() }, backoff: { backoffs += 1 })
        let values = controller.scheduledTasks()
        let consumer = Task { for await _ in values {} }
        controller.start()
        await until { factory.requests == 1 }
        first.continuation.finish()
        await until { factory.requests == 2 }
        #expect(backoffs == 1 && second.leases.first?.topic == .scheduledTasks)
        consumer.cancel()
        controller.stop()
    }

    @Test
    func `explicit reconnect without claims starts a new session using a fresh wake stream`() async {
        let first = Driver()
        let second = Driver()
        let third = Driver()
        let factory = Factory([first, second, third])
        let controller = JellyfinSocketController(sessionFactory: { factory.next() })
        controller.start()
        await until { factory.requests == 1 }
        controller.reconnect()
        await until { factory.requests == 2 }
        controller.stop()
        controller.start()
        await until { factory.requests == 3 }
        #expect(factory.requests == 3 && first.disconnects == 1 && second.disconnects == 1)
        controller.stop()
    }

    @Test
    func `owner release disconnects native output without a worker retaining the owner`() async {
        let driver = Driver()
        let factory = Factory([driver])
        var controller: JellyfinSocketController? = .init(sessionFactory: { factory.next() })
        weak let weakOwner = controller
        controller?.start()
        await until { factory.requests == 1 }
        controller = nil
        await until { weakOwner == nil }
        #expect(weakOwner == nil && driver.disconnects == 1)
    }

    @Test
    func `stopped backoff cannot allocate another old session after restart`() async throws {
        let first = Driver()
        let second = Driver()
        let factory = Factory([first, second])
        var wait: CheckedContinuation<Void, Never>?
        let controller = JellyfinSocketController(
            sessionFactory: { factory.next() },
            backoff: { await withCheckedContinuation { wait = $0 } }
        )
        let values = controller.sessions()
        let consumer = Task { for await _ in values {} }
        controller.start()
        await until { factory.requests == 1 }
        first.continuation.finish()
        await until { wait != nil }
        let continuation = try #require(wait)
        controller.stop()
        controller.start()
        await until { factory.requests == 2 }
        continuation.resume()
        for _ in 0 ..< 20 {
            await Task.yield()
        }
        #expect(factory.requests == 2 && second.disconnects == 0)
        consumer.cancel()
        controller.stop()
    }

    @Test
    func `command streams preserve FIFO values without exposing native socket events`() async {
        let driver = Driver()
        let factory = Factory([driver])
        let controller = JellyfinSocketController(sessionFactory: { factory.next() })
        let stream = controller.commands()
        var commands: [PlaystateCommand?] = []
        let consumer = Task {
            for await event in stream {
                if case let .playstate(value) = event {
                    commands.append(value.command)
                }
            }
        }
        controller.start()
        await until { factory.requests == 1 }
        driver.continuation.yield(.message(.playstateMessage(.init(data: .init(command: .pause)))))
        driver.continuation.yield(.message(.playstateMessage(.init(data: .init(command: .unpause)))))
        await until { commands.count == 2 }
        #expect(commands == [.pause, .unpause])
        consumer.cancel()
        controller.stop()
    }

    @Test(arguments: [false, true])
    func `a source created across stop or replacement is retired before subscription`(_ restart: Bool) async {
        let first = Driver()
        let second = Driver()
        let factory = Factory([first, second])
        let controller = JellyfinSocketController(sessionFactory: { factory.next() })
        let stream = controller.sessions()
        let consumer = Task { for await _ in stream {} }
        factory.onNext = { [weak controller] in
            if restart {
                controller?.start()
            } else {
                controller?.stop()
            }
        }
        controller.start()
        await until { factory.requests == (restart ? 2 : 1) }
        #expect(first.disconnects == 1 && first.leases.isEmpty)
        #expect(second.disconnects == 0)
        consumer.cancel()
        controller.stop()
        first.continuation.finish()
        second.continuation.finish()
    }

    @Test
    func `stop during subscription creation cancels its unpublished claim`() async {
        let driver = Driver()
        let factory = Factory([driver])
        let controller = JellyfinSocketController(sessionFactory: { factory.next() })
        let stream = controller.sessions()
        let consumer = Task { for await _ in stream {} }
        driver.onSubscribe = { [weak controller] in controller?.stop() }
        controller.start()
        await until { factory.requests == 1 }
        #expect(driver.leases.count == 1 && driver.leases.first?.cancelled == true)
        #expect(driver.disconnects == 1)
        consumer.cancel()
        controller.stop()
    }

    @Test
    func `a replacement started during old teardown owns the only new worker`() async {
        let first = Driver()
        let second = Driver()
        let unwanted = Driver()
        let factory = Factory([first, second, unwanted])
        let controller = JellyfinSocketController(sessionFactory: { factory.next() })
        controller.start()
        await until { factory.requests == 1 }
        first.onDisconnect = { [weak controller] in controller?.start() }
        controller.start()
        await until { factory.requests >= 2 }
        for _ in 0 ..< 20 {
            await Task.yield()
        }
        #expect(factory.requests == 2)
        controller.stop()
        first.continuation.finish()
        second.continuation.finish()
        unwanted.continuation.finish()
    }
}
