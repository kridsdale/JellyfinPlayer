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
import SwiftfinAsyncStreams
import SwiftfinNetworking
import SwiftfinPlaybackReporting
import Testing

@MainActor
private final class Sender: JellyfinRequestSending {
    struct Call { let path: String
        let body: Data?
        let delegate: (any URLSessionDataDelegate)?
    }

    var calls: [Call] = []
    var failure = false
    var gate: CheckedContinuation<Void, Never>?
    var blocked = false
    enum Failure: Error { case offline }
    func value<Value: Decodable & Sendable>(for request: Request<Value>) async throws -> Value {
        throw Failure.offline
    }

    func complete(_ request: Request<Void>) async throws {
        try await complete(request, delegate: nil)
    }

    func complete(_ request: Request<Void>, delegate: (any URLSessionDataDelegate)?) async throws {
        try calls.append(.init(path: request.url?.path ?? "", body: request.body.map { try JSONEncoder().encode($0) }, delegate: delegate))
        if blocked {
            await withCheckedContinuation { gate = $0 }
        }
        if failure {
            throw Failure.offline
        }
    }

    func wait(for count: Int) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while calls.count < count || (blocked && gate == nil) {
            if .now >= deadline {
                throw Failure.offline
            }
            await Task.yield()
        }
    }

    func release() {
        blocked = false
        gate?.resume()
        gate = nil
    }
}

private final class Delegate: NSObject, URLSessionDataDelegate {}
private func identity(sessionID: String? = nil) -> PlaybackReportIdentity {
    .init(
        itemID: "original-item",
        mediaSourceID: "original-source",
        liveStreamID: "live",
        playSessionID: "play",
        sessionID: sessionID,
        canSeek: true,
        playMethod: .directPlay
    )
}

private func payload(_ call: Sender.Call) throws -> [String: Any] {
    try JSONSerialization.jsonObject(with: #require(call.body)) as! [String: Any]
}

@Test @MainActor
func `exact start progress stop payloads and timing delegate`() async throws {
    let sender = Sender()
    let id = identity()
    let client = PlaybackReportingClient(sender: sender, identity: id)
    let delegate = Delegate()
    var snapshot = id.snapshot(positionTicks: 12, audio: 2, subtitle: 3, isPaused: false)
    try await client.send(.start, snapshot: snapshot, delegate: delegate)
    snapshot.positionTicks = 34
    snapshot.isPaused = true
    try await client.send(.progress, snapshot: snapshot, delegate: delegate)
    try await client.send(.stop, snapshot: snapshot, delegate: delegate)
    #expect(sender.calls.map(\.path) == ["/Sessions/Playing", "/Sessions/Playing/Progress", "/Sessions/Playing/Stopped"])
    #expect(sender.calls.allSatisfy { $0.delegate === delegate })
    let start = try payload(sender.calls[0])
    let progress = try payload(sender.calls[1])
    let stop = try payload(sender.calls[2])
    #expect(start["ItemId"] as? String == "original-item")
    #expect(start["MediaSourceId"] as? String == "original-source")
    #expect(start["PlaySessionId"] as? String == "play")
    #expect(start["CanSeek"] as? Bool == true)
    #expect(start["AudioStreamIndex"] as? Int == 2)
    #expect(start["SubtitleStreamIndex"] as? Int == 3)
    #expect(progress["PositionTicks"] as? Int == 34)
    #expect(progress["IsPaused"] as? Bool == true)
    #expect(stop["PositionTicks"] as? Int == 34)
    #expect(stop["LiveStreamId"] as? String == "live")
    #expect(stop["SessionId"] == nil)
    #expect(stop["AudioStreamIndex"] == nil)
}

@Test @MainActor
func `inherited session ID is preserved`() async throws {
    let sender = Sender()
    let id = identity(sessionID: "play")
    let client = PlaybackReportingClient(sender: sender, identity: id)
    try await client.send(.stop, snapshot: id.snapshot(positionTicks: nil, audio: nil, subtitle: nil))
    let stop = try payload(sender.calls[0])
    #expect(stop["SessionId"] as? String == "play")
    #expect(stop["PositionTicks"] == nil)
}

@Test @MainActor
func `changed report identity rejected before any IO`() async throws {
    let sender = Sender()
    let id = identity()
    let client = PlaybackReportingClient(sender: sender, identity: id)
    for change in 0 ..< 5 {
        var snapshot = id.snapshot(positionTicks: 1, audio: nil, subtitle: nil)
        switch change {
        case 0: snapshot.itemID = "other"
        case 1: snapshot.mediaSourceID = "other"
        case 2: snapshot.playSessionID = "other"
        case 3: snapshot.liveStreamID = "other"
        default: snapshot.sessionID = "other"
        }
        await #expect(throws: PlaybackReportingError.self) { try await client.send(.stop, snapshot: snapshot) }
    }
    #expect(sender.calls.isEmpty)
}

@Test @MainActor
func `terminal cleanup uses original transport after UI replacement`() async throws {
    let original = Sender()
    original.blocked = true
    let replacement = Sender()
    var current = original
    let id = identity()
    let client = PlaybackReportingClient(sender: current, identity: id)
    let first = id.snapshot(positionTicks: 1, audio: nil, subtitle: nil)
    let queue = PlaybackReportQueue(initial: first) { try await client.send($0.kind, snapshot: $0.snapshot) }
    try await original.wait(for: 1)
    current = replacement
    queue.finish(id.snapshot(positionTicks: 99, audio: nil, subtitle: nil))
    original.release()
    await queue.waitUntilFinished()
    #expect(current === replacement)
    #expect(replacement.calls.isEmpty)
    #expect(original.calls.map(\.path) == ["/Sessions/Playing", "/Sessions/Playing/Stopped"])
    #expect(try payload(original.calls[1])["PositionTicks"] as? Int == 99)
}

@Test @MainActor
func `cancellation before send does not issue request`() async {
    let sender = Sender()
    let id = identity()
    let client = PlaybackReportingClient(sender: sender, identity: id)
    let task = Task { @MainActor in
        withUnsafeCurrentTask { $0?.cancel() }
        await #expect(throws: CancellationError.self) {
            try await client.send(.start, snapshot: id.snapshot(positionTicks: 0, audio: nil, subtitle: nil))
        }
    }
    await task.value
    #expect(sender.calls.isEmpty)
}

@Test @MainActor
func `original send failure is preserved`() async {
    let sender = Sender()
    sender.failure = true
    let id = identity()
    let client = PlaybackReportingClient(sender: sender, identity: id)
    await #expect(throws: Sender.Failure.self) { try await client.send(
        .progress,
        snapshot: id.snapshot(positionTicks: 1, audio: nil, subtitle: nil)
    ) }
    #expect(sender.calls.count == 1)
}
