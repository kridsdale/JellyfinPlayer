//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

// SPDX-License-Identifier: MPL-2.0
import Foundation
@testable import SwiftfinAudioSession
import Testing

private enum Failure: Error { case activation }
private actor Operations {
    var activations = 0
    var deactivations = 0
    var failNextActivation = false
    func activate() throws {
        activations += 1
        if failNextActivation {
            failNextActivation = false
            throw Failure.activation
        }
    }

    func deactivate() {
        deactivations += 1
    }

    func failOnce() {
        failNextActivation = true
    }

    var counts: [Int] {
        [activations, deactivations]
    }
}

private actor Gate {
    private var entered = false
    private var opened = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var observers: [CheckedContinuation<Void, Never>] = []
    func wait() async {
        entered = true
        observers.forEach { $0.resume() }
        observers.removeAll()
        if !opened {
            await withCheckedContinuation { waiters.append($0) }
        }
    }

    func waitForEntry() async {
        if !entered {
            await withCheckedContinuation { observers.append($0) }
        }
    }

    func open() {
        opened = true
        waiters.forEach { $0.resume() }
        waiters.removeAll()
    }
}

@MainActor
private func fixture(_ operations: Operations) -> PlaybackAudioSession {
    PlaybackAudioSession(activate: { try await operations.activate() }, deactivate: { await operations.deactivate() })
}

@Test @MainActor
func `simultaneous leases activate once and only final release deactivates`() async throws {
    let calls = Operations(), audio = fixture(calls)
    let first = UUID(), second = UUID()
    let a = audio.acquire(first), b = audio.acquire(second)
    try await a.value
    try await b.value
    #expect(await calls.counts == [1, 0])
    audio.release(first)
    try await audio.finishPendingOperations()
    #expect(await calls.counts == [1, 0])
    audio.release(second)
    try await audio.finishPendingOperations()
    #expect(await calls.counts == [1, 1])
    audio.release(second)
    try await audio.finishPendingOperations()
    #expect(await calls.counts == [1, 1])
}

@Test @MainActor
func `delayed old player drain cannot deactivate a replacement lease`() async throws {
    let calls = Operations(), audio = fixture(calls), drain = Gate()
    let old = UUID(), replacement = UUID()
    try await audio.acquire(old).value
    audio.release(old, after: { await drain.wait()
        return true
    })
    await drain.waitForEntry()
    let pending = audio.acquire(replacement)
    await drain.open()
    try await pending.value
    #expect(await calls.counts == [1, 0])
    audio.release(replacement)
    try await audio.finishPendingOperations()
    #expect(await calls.counts == [1, 1])
}

@Test @MainActor
func `owner released before queued activation cannot activate output`() async throws {
    let calls = Operations(), activation = Gate()
    let audio = PlaybackAudioSession(activate: { await activation.wait()
        try await calls.activate()
    }, deactivate: { await calls.deactivate() })
    let first = UUID(), cancelled = UUID()
    let a = audio.acquire(first)
    await activation.waitForEntry()
    let b = audio.acquire(cancelled)
    audio.release(cancelled)
    await activation.open()
    try await a.value
    do { try await b.value
        Issue.record("Removed lease activated")
    } catch { #expect(error is CancellationError) }
    try await audio.finishPendingOperations()
    #expect(await calls.counts == [1, 0])
    audio.release(first)
    try await audio.finishPendingOperations()
    #expect(await calls.counts == [1, 1])
}

@Test @MainActor
func `failed activation does not mark session active and subsequent owner retries`() async throws {
    let calls = Operations(), audio = fixture(calls)
    await calls.failOnce()
    let first = UUID(), next = UUID()
    do { try await audio.acquire(first).value
        Issue.record("Injected failure was lost")
    } catch { #expect(error is Failure) }
    try await audio.acquire(next).value
    #expect(await calls.counts == [2, 0])
    audio.release(first)
    audio.release(next)
    try await audio.finishPendingOperations()
    #expect(await calls.counts == [2, 1])
}

@Test @MainActor
func `undrained native output keeps audio active until a later successful drain`() async throws {
    let calls = Operations(), audio = fixture(calls)
    let first = UUID(), next = UUID()
    try await audio.acquire(first).value
    audio.release(first, after: { false })
    try await audio.finishPendingOperations()
    #expect(await calls.counts == [1, 0])
    try await audio.acquire(next).value
    #expect(await calls.counts == [1, 0])
    audio.release(next)
    try await audio.finishPendingOperations()
    #expect(await calls.counts == [1, 1])
}

@Test @MainActor
func `interruption requires new activation while preserving the owner lease`() async throws {
    let calls = Operations(), audio = fixture(calls), owner = UUID()
    try await audio.acquire(owner).value
    audio.wasInterrupted()
    try await audio.acquire(owner).value
    #expect(await calls.counts == [2, 0])
    audio.release(owner)
    try await audio.finishPendingOperations()
    #expect(await calls.counts == [2, 1])
}
