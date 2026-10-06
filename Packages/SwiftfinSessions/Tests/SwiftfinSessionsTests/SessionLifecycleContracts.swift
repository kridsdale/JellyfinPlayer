//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation
import SwiftfinSessions
import Testing

@MainActor
private final class Log { var events: [String] = [] }
@MainActor
private final class Resource: SessionResource {
    let name: String
    let log: Log
    var continuation: CheckedContinuation<Void, Never>?
    let suspended: Bool
    var onStart: (@MainActor () -> Void)?
    init(_ name: String, log: Log, suspended: Bool = false) {
        self.name = name
        self.log = log
        self.suspended = suspended
    }

    func prepare() async {
        log.events.append("prepare-" + name)
        if suspended {
            await withCheckedContinuation { continuation = $0 }
        }
        log.events.append("prepared-" + name)
    }

    func start() {
        log.events.append("start-" + name)
        onStart?()
    }

    func stop() {
        log.events.append("stop-" + name)
    }
}

@MainActor
private final class Session: AccountSessionLifecycle {
    let sessionIdentity: AccountSessionIdentity
    let lifecycle: SessionLifecycle
    init(user: String, server: String = "server", resources: [any SessionResource]) {
        sessionIdentity = .init(serverID: server, userID: user)
        lifecycle = .init(resources: resources)
    }

    func prepare() async {
        await lifecycle.prepare()
    }

    func start() {
        lifecycle.start()
    }

    func stop() {
        lifecycle.stop()
    }
}

@Suite(.serialized) @MainActor
struct SessionLifecycleContracts {
    @Test
    func `resources prepare and start in order and stop in reverse order once`() async {
        let log = Log()
        let lifecycle = SessionLifecycle(resources: [Resource("one", log: log), Resource("two", log: log)])
        await lifecycle.prepare()
        lifecycle.start()
        lifecycle.stop()
        lifecycle.stop()
        #expect(log.events == [
            "prepare-one",
            "prepared-one",
            "prepare-two",
            "prepared-two",
            "start-one",
            "start-two",
            "stop-two",
            "stop-one"
        ])
    }

    @Test
    func `a resource stopping during activation prevents later resources from starting`() async {
        let log = Log()
        let first = Resource("one", log: log)
        let lifecycle = SessionLifecycle(resources: [first, Resource("two", log: log)])
        first.onStart = { [weak lifecycle] in lifecycle?.stop() }
        await lifecycle.prepare()
        lifecycle.start()
        #expect(log.events.suffix(3) == ["start-one", "stop-two", "stop-one"])
        #expect(!log.events.contains("start-two"))
    }

    @Test
    func `stop during noncooperating preparation prevents later preparation and activation`() async throws {
        let log = Log()
        let first = Resource("one", log: log, suspended: true)
        let lifecycle = SessionLifecycle(resources: [first, Resource("two", log: log)])
        let task = Task { await lifecycle.prepare() }
        for _ in 0 ..< 100 where first.continuation == nil {
            await Task.yield()
        }
        let continuation = try #require(first.continuation)
        lifecycle.stop()
        continuation.resume()
        await task.value
        lifecycle.start()
        #expect(!log.events.contains("prepare-two") && !log.events.contains("start-one"))
        #expect(log.events.suffix(2) == ["prepared-one", "stop-one"])
    }

    @Test
    func `cancelled preparation releases all resources and does not start`() async throws {
        let log = Log()
        let first = Resource("one", log: log, suspended: true)
        let lifecycle = SessionLifecycle(resources: [first, Resource("two", log: log)])
        let task = Task { await lifecycle.prepare() }
        for _ in 0 ..< 100 where first.continuation == nil {
            await Task.yield()
        }
        let continuation = try #require(first.continuation)
        task.cancel()
        continuation.resume()
        await task.value
        lifecycle.start()
        #expect(!log.events.contains("prepare-two") && !log.events.contains("start-one"))
        #expect(log.events.contains("stop-two") && log.events.contains("stop-one"))
    }

    @Test
    func `owner release tears down resources without a retained owner`() async {
        let log = Log()
        var owner: SessionLifecycle? = .init(resources: [Resource("one", log: log)])
        await owner?.prepare()
        owner?.start()
        weak let weakOwner = owner
        owner = nil
        #expect(weakOwner == nil && log.events.last == "stop-one")
    }

    @Test
    func `replacement publishes after preparation and before activation`() async {
        let log = Log()
        let coordinator = ActiveSessionCoordinator<Session> { session, changed in
            log.events.append("publish-" + (session?.sessionIdentity.userID ?? "nil") + "-" + String(changed))
        }
        await coordinator.replace(with: Session(user: "kid", resources: [Resource("one", log: log)]))
        #expect(log.events == ["prepare-one", "prepared-one", "publish-kid-true", "start-one"])
        await coordinator.replace(with: nil)
        #expect(log.events.suffix(2) == ["stop-one", "publish-nil-true"])
        #expect(coordinator.current == nil)
    }

    @Test
    func `later replacement wins over a suspended earlier session and old resources never start`() async throws {
        let log = Log()
        let first = Resource("old", log: log, suspended: true)
        var publications: [String] = []
        let coordinator = ActiveSessionCoordinator<Session> { session, _ in publications.append(session?.sessionIdentity.userID ?? "nil") }
        let old = Session(user: "old", resources: [first])
        let pending = Task { await coordinator.replace(with: old) }
        for _ in 0 ..< 100 where first.continuation == nil {
            await Task.yield()
        }
        let continuation = try #require(first.continuation)
        let new = Session(user: "new", resources: [Resource("new", log: log)])
        await coordinator.replace(with: new)
        continuation.resume()
        await pending.value
        #expect(publications == ["new"] && coordinator.current === new)
        #expect(!log.events.contains("start-old") && log.events.contains("start-new"))
    }

    @Test
    func `same account replacement preserves identity change semantics while restarting resources`() async throws {
        let log = Log()
        var changes: [Bool] = []
        let coordinator = ActiveSessionCoordinator<Session> { _, changed in changes.append(changed) }
        await coordinator.replace(with: Session(user: "kid", resources: [Resource("old", log: log)]))
        await coordinator.replace(with: Session(user: "kid", resources: [Resource("new", log: log)]))
        await coordinator.replace(with: Session(user: "kid", server: "other", resources: []))
        #expect(changes == [true, false, true])
        #expect(try #require(log.events.firstIndex(of: "stop-old")) < log.events.firstIndex(of: "prepare-new")!)
    }

    @Test
    func `cancelled replacement never publishes a prepared session`() async throws {
        let log = Log()
        let resource = Resource("pending", log: log, suspended: true)
        var publications = 0
        let coordinator = ActiveSessionCoordinator<Session> { _, _ in publications += 1 }
        let task = Task { await coordinator.replace(with: Session(user: "kid", resources: [resource])) }
        for _ in 0 ..< 100 where resource.continuation == nil {
            await Task.yield()
        }
        let continuation = try #require(resource.continuation)
        task.cancel()
        continuation.resume()
        await task.value
        #expect(coordinator.current == nil && publications == 0)
        #expect(!log.events.contains("start-pending"))
    }

    @Test
    func `stop from publication cannot reactivate the published session`() async {
        let log = Log()
        var coordinator: ActiveSessionCoordinator<Session>?
        coordinator = ActiveSessionCoordinator { _, _ in coordinator?.stop() }
        await coordinator?.replace(with: Session(user: "kid", resources: [Resource("one", log: log)]))
        #expect(coordinator?.current == nil && !log.events.contains("start-one"))
        coordinator = nil
    }

    @Test
    func `repeated activation and replacing the exact active instance are idempotent`() async {
        let log = Log()
        var publications = 0
        let coordinator = ActiveSessionCoordinator<Session> { _, _ in publications += 1 }
        let session = Session(user: "kid", resources: [Resource("one", log: log)])
        await coordinator.replace(with: session)
        session.start()
        await coordinator.replace(with: session)
        #expect(publications == 1 && log.events.filter { $0 == "start-one" }.count == 1)
        #expect(!log.events.contains("stop-one"))
    }
}
