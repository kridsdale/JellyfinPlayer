//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

// SPDX-License-Identifier: MPL-2.0
import Foundation
import KidsDiagnostics
@testable import KidsPlayback
import Testing

private actor ReportGate {
    enum Failure: Error { case fixture }
    typealias Kind = KidsPlaybackReporter<Int>.Kind
    private(set) var kinds: [Kind] = []
    private(set) var positions: [Int] = []
    private(set) var peakActive = 0
    private var active = 0
    private let blocked: Set<Int>
    private let failing: Set<Int>
    private var pending: [Int: CheckedContinuation<Void, Error>] = [:]

    init(blocked: Set<Int> = [], failing: Set<Int> = []) {
        self.blocked = blocked
        self.failing = failing
    }

    func send(_ event: KidsPlaybackReporter<Int>.Event) async throws {
        kinds.append(event.kind)
        positions.append(event.snapshot)
        let number = kinds.count
        active += 1
        peakActive = max(peakActive, active)
        defer { active -= 1 }
        if blocked.contains(number) {
            try await withCheckedThrowingContinuation { pending[number] = $0 }
        }
        if failing.contains(number) {
            throw Failure.fixture
        }
    }

    func wait(for requests: Int) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while kinds.count < requests {
            if .now >= deadline {
                throw Failure.fixture
            }
            await Task.yield()
        }
    }

    func release(_ number: Int) {
        pending.removeValue(forKey: number)?.resume()
    }
}

@Test @MainActor
func `stop is retained even when a slow start blocks hundreds of updates`() async throws {
    let gate = ReportGate(blocked: [1])
    let reporter = KidsPlaybackReporter(initial: 0) { try await gate.send($0) }
    try await gate.wait(for: 1)
    for position in 1 ... 1000 {
        reporter.update(position)
    }
    reporter.finish(1001)
    reporter.update(2000)
    reporter.finish(3000)
    await gate.release(1)
    await reporter.waitUntilFinished()
    #expect(await gate.kinds == [.start, .stop])
    #expect(await gate.positions == [0, 1001])
    #expect(await gate.peakActive == 1)
}

@Test @MainActor
func `slow progress coalesces to the newest snapshot without overlapping requests`() async throws {
    let gate = ReportGate(blocked: [2])
    let reporter = KidsPlaybackReporter(initial: 0) { try await gate.send($0) }
    try await gate.wait(for: 1)
    reporter.update(1)
    try await gate.wait(for: 2)
    for position in 2 ... 1000 {
        reporter.update(position)
    }
    await gate.release(2)
    try await gate.wait(for: 3)
    reporter.finish(1001)
    await reporter.waitUntilFinished()
    #expect(await gate.kinds == [.start, .progress, .progress, .stop])
    #expect(await gate.positions == [0, 1, 1000, 1001])
    #expect(await gate.peakActive == 1)
}

@Test @MainActor
func `an unacknowledged start retries on a later snapshot before any progress or stop`() async throws {
    let gate = ReportGate(failing: [1])
    let reporter = KidsPlaybackReporter(initial: 0) { try await gate.send($0) }
    try await gate.wait(for: 1)
    reporter.update(10)
    try await gate.wait(for: 2)
    reporter.finish(11)
    await reporter.waitUntilFinished()
    #expect(await gate.kinds == [.start, .start, .stop])
    #expect(await gate.positions == [0, 10, 11])
    #expect(await gate.peakActive == 1)
}

@Test @MainActor
func `a failed progress report does not prevent a newer position or final stop`() async throws {
    let gate = ReportGate(failing: [2])
    let reporter = KidsPlaybackReporter(initial: 0) { try await gate.send($0) }
    try await gate.wait(for: 1)
    reporter.update(1)
    try await gate.wait(for: 2)
    reporter.update(2)
    try await gate.wait(for: 3)
    reporter.finish(3)
    await reporter.waitUntilFinished()
    #expect(await gate.kinds == [.start, .progress, .progress, .stop])
    #expect(await gate.positions == [0, 1, 2, 3])
    #expect(await gate.peakActive == 1)
}

@Test @MainActor
func `unreachable reporting stays finite at finish and never sends unauthenticated progress`() async throws {
    let gate = ReportGate(failing: [1, 2])
    let reporter = KidsPlaybackReporter(initial: 0) { try await gate.send($0) }
    try await gate.wait(for: 1)
    reporter.finish(5)
    await reporter.waitUntilFinished()
    #expect(await gate.kinds == [.start, .start])
    #expect(await gate.positions == [0, 5])
}

@Test @MainActor
func `cancellation prevents buffered progress from escaping an obsolete reporting session`() async throws {
    let gate = ReportGate(blocked: [1])
    let reporter = KidsPlaybackReporter(initial: 0) { try await gate.send($0) }
    try await gate.wait(for: 1)
    reporter.update(1)
    reporter.cancel()
    reporter.finish(2)
    await gate.release(1)
    await reporter.waitUntilFinished()
    #expect(await gate.kinds == [.start])
    #expect(await gate.positions == [0])
}

@Test @MainActor
func `a delayed old stop cannot overtake the next videos start`() async throws {
    let gate = ReportGate(blocked: [1, 2])
    let previous = KidsPlaybackReporter(initial: 0) { try await gate.send($0) }
    try await gate.wait(for: 1)
    previous.finish(10)
    let next = KidsPlaybackReporter(initial: 100, after: previous) { try await gate.send($0) }
    next.update(101)
    await gate.release(1)
    try await gate.wait(for: 2)
    #expect(await gate.kinds == [.start, .stop])
    #expect(await gate.positions == [0, 10])
    await gate.release(2)
    try await gate.wait(for: 3)
    next.finish(110)
    await next.waitUntilFinished()
    let kinds = await gate.kinds
    let positions = await gate.positions
    #expect(kinds.prefix(3).elementsEqual([.start, .stop, .start]))
    #expect(positions.prefix(3).elementsEqual([0, 10, 100]))
    #expect(kinds.last == .stop)
    #expect(positions.last == 110)
    #expect(await gate.peakActive == 1)
}
