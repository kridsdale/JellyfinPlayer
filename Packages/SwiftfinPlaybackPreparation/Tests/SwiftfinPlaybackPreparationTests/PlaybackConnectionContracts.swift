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
import SwiftfinNetworking
import SwiftfinPlaybackPreparation
import SwiftfinPlaybackReporting
import Testing

@MainActor
private final class ConnectionSender: JellyfinRequestSending, PlaybackURLResolving {
    var calls: [String] = []
    let serverURL = URL(string: "https://example.invalid")!
    func streamURL(path: String) -> URL? {
        URL(string: path, relativeTo: serverURL)
    }

    func streamURL(for request: Request<Data>) -> URL? {
        serverURL.appending(path: request.url?.path ?? "")
    }

    func value<Value: Decodable & Sendable>(for request: Request<Value>) async throws -> Value {
        calls.append(request.url?.path ?? "")
        return try JSONDecoder().decode(Value.self, from: Data(#"{"Id":"item"}"#.utf8))
    }

    func complete(_ request: Request<Void>) async throws {
        calls.append(request.url?.path ?? "")
    }
}

@MainActor
private final class CurrentConnection {
    var sender: ConnectionSender
    init(_ sender: ConnectionSender) {
        self.sender = sender
    }
}

@Test @MainActor
func `preparation expires while final report retains original connection`() async throws {
    let original = ConnectionSender()
    let replacement = ConnectionSender()
    let current = CurrentConnection(original)
    let connection = PlaybackConnection(sender: original, urls: original, userID: "user") {
        current.sender === original
    }
    let item = try await connection.preparation.item(id: "item")
    #expect(item.id == "item")
    let identity = PlaybackReportIdentity(itemID: "item", mediaSourceID: "source", liveStreamID: nil, playSessionID: "play")
    let reports = connection.reportingClient(identity: identity)
    try await reports.send(.start, snapshot: identity.snapshot(positionTicks: 0, audio: nil, subtitle: nil))
    current.sender = replacement
    await #expect(throws: CancellationError.self) { try await connection.preparation.item(id: "item") }
    #expect(throws: CancellationError.self) { try connection.preparation.checkBinding() }
    // Creating the observer after replacement must still capture the original sender.
    let terminal = connection.reportingClient(identity: identity)
    try await terminal.send(.stop, snapshot: identity.snapshot(positionTicks: 123, audio: nil, subtitle: nil))
    #expect(original.calls == ["/Items/item", "/Sessions/Playing", "/Sessions/Playing/Stopped"])
    #expect(replacement.calls.isEmpty)
}
