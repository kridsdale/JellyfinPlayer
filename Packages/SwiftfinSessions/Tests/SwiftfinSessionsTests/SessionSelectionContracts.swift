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
private final class SelectionLog { var events: [String] = [] }
@MainActor
private final class SelectedSession: AccountSessionLifecycle {
    let sessionIdentity: AccountSessionIdentity
    let log: SelectionLog
    var paused = false
    var continuation: CheckedContinuation<Void, Never>?
    init(_ user: String, server: String = "server", log: SelectionLog) {
        sessionIdentity = .init(serverID: server, userID: user)
        self.log = log
    }

    func prepare() async {
        log.events.append("prepare-" + sessionIdentity.userID)
        if paused {
            await withCheckedContinuation { continuation = $0 }
        }
    }

    func start() {
        log.events.append("start-" + sessionIdentity.userID)
    }

    func stop() {
        log.events.append("stop-" + sessionIdentity.userID)
    }
}

@MainActor
private final class NativePrompt {
    enum Failure: Error { case denied }
    var continuation: CheckedContinuation<Void, Never>?
    func wait() async {
        await withCheckedContinuation { continuation = $0 }
    }

    func release() {
        continuation?.resume()
        continuation = nil
    }
}

@MainActor
private func waitUntil(_ ready: () -> Bool) async throws {
    let deadline = ContinuousClock.now.advanced(by: .seconds(3))
    while !ready() {
        guard .now < deadline else { throw NativePrompt.Failure.denied }
        await Task.yield()
    }
}

@MainActor
private func owner(_ log: SelectionLog) -> (ActiveSessionCoordinator<SelectedSession>, SessionSelectionCoordinator<SelectedSession>) {
    let active = ActiveSessionCoordinator<SelectedSession> { session, _ in
        log.events.append("publish-" + (session?.sessionIdentity.userID ?? "nil"))
    }
    return (active, SessionSelectionCoordinator(sessions: active))
}

@Suite(.serialized) @MainActor
struct SessionSelectionContracts {
    @Test
    func `authentication and persisted selection precede publication then routing`() async throws {
        let log = SelectionLog()
        let (_, selections) = owner(log)
        let request = try #require(try selections.begin(priority: .explicit))
        try await selections.activate(request, with: SelectedSession("kid", log: log), prepare: { _ in
            log.events.append("authenticate")
        }, willSelect: { _ in log.events.append("persist") }, didSelect: { _ in log.events.append("route") })
        #expect(log.events == ["authenticate", "persist", "prepare-kid", "publish-kid", "start-kid", "route"])
        try request.check()
    }

    @Test
    func `pending explicit choice blocks passive restore until completion`() async throws {
        let log = SelectionLog()
        let (_, selections) = owner(log)
        let request = try #require(try selections.begin(priority: .explicit))
        #expect(try selections.begin(priority: .restoration) == nil)
        try request.check()
        try await selections.activate(request, with: nil)
        #expect(try selections.begin(priority: .restoration) != nil)
    }

    @Test
    func `failed and reentrant preflight cannot retire a newer choice`() throws {
        let log = SelectionLog()
        let (_, selections) = owner(log)
        let first = try #require(try selections.begin(priority: .explicit))
        #expect(throws: NativePrompt.Failure.self) {
            try selections.begin(priority: .explicit, validate: { throw NativePrompt.Failure.denied })
        }
        try first.check()
        var newer: SessionSelectionCoordinator<SelectedSession>.Request?
        #expect(throws: CancellationError.self) {
            try selections.begin(priority: .restoration, validate: { newer = try selections.begin(priority: .explicit) })
        }
        try #require(newer).check()
        #expect(throws: CancellationError.self) { try first.check() }
    }

    @Test
    func `new explicit choice defeats delayed native authentication success or failure`() async throws {
        for failing in [false, true] {
            let log = SelectionLog(), prompt = NativePrompt()
            let (active, selections) = owner(log)
            let first = try #require(try selections.begin(priority: .explicit))
            let task = Task {
                try await selections.activate(first, with: SelectedSession("old", log: log), prepare: { _ in
                    await prompt.wait()
                    if failing {
                        throw NativePrompt.Failure.denied
                    }
                }, willSelect: { _ in log.events.append("persist-old") }, didSelect: { _ in log.events.append("route-old") })
            }
            try await waitUntil { prompt.continuation != nil }
            let next = try #require(try selections.begin(priority: .explicit))
            let selected = SelectedSession("new", log: log)
            try await selections.activate(next, with: selected)
            prompt.release()
            await #expect(throws: CancellationError.self) { try await task.value }
            #expect(active.current === selected)
            #expect(!log.events.contains("persist-old") && !log.events.contains("publish-old") && !log.events.contains("route-old"))
        }
    }

    @Test
    func `failed authentication preserves existing running session and releases restore admission`() async throws {
        let log = SelectionLog()
        let (active, selections) = owner(log)
        let current = SelectedSession("current", log: log)
        await active.replace(with: current)
        let before = log.events
        let request = try #require(try selections.begin(priority: .explicit))
        await #expect(throws: NativePrompt.Failure.self) {
            try await selections.activate(
                request,
                with: SelectedSession("next", log: log),
                prepare: { _ in throw NativePrompt.Failure.denied }
            )
        }
        #expect(active.current === current && log.events == before)
        #expect(try selections.begin(priority: .restoration) != nil)
    }

    @Test
    func `persist callback reentry prevents old teardown and preparation`() async throws {
        let log = SelectionLog()
        let (active, selections) = owner(log)
        let current = SelectedSession("current", log: log)
        await active.replace(with: current)
        let request = try #require(try selections.begin(priority: .explicit))
        var next: SessionSelectionCoordinator<SelectedSession>.Request?
        await #expect(throws: CancellationError.self) {
            try await selections.activate(request, with: SelectedSession("old", log: log), willSelect: { _ in
                next = try selections.begin(priority: .explicit)
            })
        }
        try #require(next).check()
        #expect(active.current === current && !log.events.contains("stop-current") && !log.events.contains("prepare-old"))
    }

    @Test
    func `new choice replaces a noncooperating preparation without old route or start`() async throws {
        let log = SelectionLog()
        let (active, selections) = owner(log)
        let first = try #require(try selections.begin(priority: .restoration))
        let old = SelectedSession("old", log: log)
        old.paused = true
        let task = Task { try await selections.activate(first, with: old, didSelect: { _ in log.events.append("route-old") }) }
        try await waitUntil { old.continuation != nil }
        let continuation = try #require(old.continuation)
        let request = try #require(try selections.begin(priority: .explicit))
        let new = SelectedSession("new", log: log)
        try await selections.activate(request, with: new)
        continuation.resume()
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(active.current === new && !log.events.contains("start-old") && !log.events.contains("route-old"))
    }

    @Test
    func `checkpoint between routing effects rejects synchronous account reentry`() async throws {
        let log = SelectionLog()
        let (_, selections) = owner(log)
        let request = try #require(try selections.begin(priority: .explicit))
        var next: SessionSelectionCoordinator<SelectedSession>.Request?
        await #expect(throws: CancellationError.self) {
            try await selections.activate(request, with: nil, didSelect: { checkpoint in
                log.events.append("first-route")
                next = try selections.begin(priority: .explicit)
                try checkpoint()
                log.events.append("second-route")
            })
        }
        #expect(log.events.contains("first-route") && !log.events.contains("second-route"))
        try #require(next).check()
        #expect(try selections.begin(priority: .restoration) == nil)
    }

    @Test
    func `requests cannot be replayed or transferred to another owner`() async throws {
        let log = SelectionLog()
        let (_, selections) = owner(log)
        let (_, other) = owner(log)
        let request = try #require(try selections.begin(priority: .explicit))
        await #expect(throws: CancellationError.self) { try await other.activate(request, with: nil) }
        try await selections.activate(request, with: nil)
        let count = log.events.count
        await #expect(throws: CancellationError.self) { try await selections.activate(request, with: nil) }
        #expect(log.events.count == count)
    }

    @Test
    func `released owner invalidates unexecuted requests`() throws {
        let log = SelectionLog()
        var selections: SessionSelectionCoordinator<SelectedSession>? = owner(log).1
        let request = try #require(try selections?.begin(priority: .explicit))
        weak let weakOwner = selections
        selections = nil
        #expect(weakOwner == nil)
        #expect(throws: CancellationError.self) { try request.check() }
    }

    @Test
    func `cancelled queued choice releases passive restoration without effects`() async throws {
        let log = SelectionLog()
        let (_, selections) = owner(log)
        let request = try #require(try selections.begin(priority: .explicit))
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            try await selections.activate(request, with: SelectedSession("cancelled", log: log))
        }
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(log.events.isEmpty)
        #expect(try selections.begin(priority: .restoration) != nil)
    }

    @Test
    func `duplicate in flight cannot release the original explicit admission`() async throws {
        let log = SelectionLog(), prompt = NativePrompt()
        let (_, selections) = owner(log)
        let request = try #require(try selections.begin(priority: .explicit))
        let task = Task { try await selections.activate(request, with: nil, prepare: { _ in await prompt.wait() }) }
        try await waitUntil { prompt.continuation != nil }
        await #expect(throws: CancellationError.self) { try await selections.activate(request, with: nil) }
        #expect(try selections.begin(priority: .restoration) == nil)
        prompt.release()
        try await task.value
        #expect(try selections.begin(priority: .restoration) != nil)
    }

    @Test
    func `resolved login handoff adds binding without replacing newer intent`() async throws {
        let log = SelectionLog()
        let (_, selections) = owner(log)
        let login = try #require(try selections.begin(priority: .explicit))
        let admitted = login.validating {}
        let next = try #require(try selections.begin(priority: .explicit))
        await #expect(throws: CancellationError.self) { try await selections.activate(admitted, with: SelectedSession("old", log: log)) }
        try next.check()
        #expect(log.events.isEmpty)
    }

    @Test
    func `added binding expiry and reentry cannot reach resource publication`() async throws {
        for reentrant in [false, true] {
            let log = SelectionLog()
            let (_, selections) = owner(log)
            let login = try #require(try selections.begin(priority: .explicit))
            let admitted = login.validating {
                if reentrant {
                    _ = try selections.begin(priority: .explicit)
                } else {
                    throw NativePrompt.Failure.denied
                }
            }
            await #expect(throws: (any Error).self) {
                try await selections.activate(admitted, with: SelectedSession("old", log: log))
            }
            #expect(log.events.isEmpty)
        }
    }

    @Test
    func `abandoned pending login releases restoration but cannot cancel a newer choice`() throws {
        let log = SelectionLog()
        let (_, selections) = owner(log)
        let first = try #require(try selections.begin(priority: .explicit))
        selections.cancelPending(first)
        #expect(throws: CancellationError.self) { try first.check() }
        let restored = try #require(try selections.begin(priority: .restoration))
        let new = try #require(try selections.begin(priority: .explicit))
        selections.cancelPending(restored)
        try new.check()
        #expect(try selections.begin(priority: .restoration) == nil)
    }

    @Test
    func `host disappearance during publication cannot abandon its active handoff`() async throws {
        let log = SelectionLog()
        var selections: SessionSelectionCoordinator<SelectedSession>?
        var request: SessionSelectionCoordinator<SelectedSession>.Request?
        let active = ActiveSessionCoordinator<SelectedSession> { _, _ in
            if let request {
                selections?.cancelPending(request)
            }
        }
        selections = SessionSelectionCoordinator(sessions: active)
        let owner = try #require(selections)
        request = try owner.begin(priority: .explicit)
        let session = SelectedSession("kid", log: log)
        try await owner.activate(#require(request), with: session)
        #expect(active.current === session && log.events.contains("start-kid"))
        try #require(request).check()
        selections = nil
    }

    @Test
    func `account view identity includes server as well as user`() {
        let first = AccountSessionIdentity(serverID: "one", userID: "same")
        let second = AccountSessionIdentity(serverID: "two", userID: "same")
        #expect(Set([first, second]).count == 2)
    }
}
