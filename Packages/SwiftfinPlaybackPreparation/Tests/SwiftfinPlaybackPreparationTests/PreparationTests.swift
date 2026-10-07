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
import Testing

private enum StubError: Error { case offline }
@MainActor
private final class Gate {
    var continuation: CheckedContinuation<Void, Never>?
    func wait() async {
        await withCheckedContinuation { continuation = $0 }
    }

    func finish() {
        continuation?.resume()
        continuation = nil
    }
}

@MainActor
private final class Binding { var current = true }
private struct Captured {
    let path: String
    let method: String
    let query: [String: String]
    let body: Data?
    let headers: [String: String]
    let rawData: Data?
}

@MainActor
private final class Sender: JellyfinRequestSending {
    var calls: [Captured] = []
    var responses: [String: Data] = [:]
    var gatePath: String?
    var gate: Gate?
    var failure = false
    var failingPath: String?
    private func capture(_ request: Request<some Any>) throws {
        let pairs = (request.query ?? []).compactMap { k, v in v.map { (k, $0) } }
        try calls.append(.init(
            path: request.url?.path ?? "",
            method: request.method.rawValue,
            query: Dictionary(grouping: pairs, by: { $0.0 }).mapValues { $0.map(\.1).joined(separator: ",") },
            body: request.body.map { try JSONEncoder().encode($0) },
            headers: request.headers ?? [:],
            rawData: request.body as? Data
        ))
    }

    func value<Value: Decodable & Sendable>(for request: Request<Value>) async throws -> Value {
        try capture(request)
        if let gate, gatePath == nil || gatePath == request.url?.path {
            await gate.wait()
        }
        if failure || request.url?.path == failingPath {
            throw StubError.offline
        }
        let data = responses[request.url?.path ?? ""] ?? Data((String(describing: Value.self).hasPrefix("Array<") ? "[]" : "{}").utf8)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(Value.self, from: data)
    }

    func complete(_ request: Request<Void>) async throws {
        try capture(request)
        if let gate, gatePath == nil || gatePath == request.url?.path {
            await gate.wait()
        }
        if failure || request.url?.path == failingPath {
            throw StubError.offline
        }
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

import SwiftfinPlaybackPreparation

@MainActor
private final class URLResolver: PlaybackURLResolving {
    var paths: [String] = []
    var requests: [Request<Data>] = []
    var fail = false
    func streamURL(path: String) -> URL? {
        paths.append(path)
        return fail ? nil : URL(string: path, relativeTo: URL(string: "http://example.invalid/base/")!)?.absoluteURL
    }

    func streamURL(for request: Request<Data>) -> URL? {
        requests.append(request)
        return fail ? nil : URL(string: "http://example.invalid/static")
    }
}

private func object(_ data: Data) throws -> [String: Any] {
    try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
}

@Suite("Playback preparation policies")
struct PreparationPolicyTests {
    @Test
    func `absent item and sources have typed errors`() {
        #expect(throws: PlaybackPreparationError.self) { try PlaybackPreparationPolicy.initialSource(
            in: .init(),
            preferred: .init(id: "override")
        ) }
        #expect(throws: PlaybackPreparationError.self) { try PlaybackPreparationPolicy.initialSource(in: .init(id: "item"), preferred: nil)
        }
        #expect(throws: PlaybackPreparationError.self) { try PlaybackPreparationPolicy.resolveSource(in: nil, initial: .init()) }
        #expect(throws: PlaybackPreparationError.self) { try PlaybackPreparationPolicy.resolveSource(in: [], initial: .init()) }
    }

    @Test
    func `preferred source overrides first and legacy resolution precedence is preserved`() throws {
        let initial = MediaSourceInfo(eTag: "wanted", id: "initial")
        #expect(try PlaybackPreparationPolicy.initialSource(in: .init(id: "item", mediaSources: [.init(id: "first")]), preferred: initial)
            .id == "initial")
        #expect(try PlaybackPreparationPolicy.initialSource(in: .init(id: "item", mediaSources: [.init(id: "first")]), preferred: nil)
            .id == "first")
        #expect(try PlaybackPreparationPolicy.resolveSource(
            in: [.init(eTag: "other", id: "first"), .init(eTag: "wanted", id: "tag")],
            initial: initial
        ).id == "tag")
        #expect(try PlaybackPreparationPolicy.resolveSource(
            in: [.init(eTag: "other", id: "open", openToken: "contains-open-token"), .init(eTag: "other", id: "initial")],
            initial: initial
        ).id == "open")
        #expect(try PlaybackPreparationPolicy.resolveSource(
            in: [.init(eTag: "other", id: "first"), .init(eTag: "other", id: "initial")],
            initial: initial
        ).id == "initial")
        #expect(try PlaybackPreparationPolicy.resolveSource(in: [.init(eTag: "other", id: "first")], initial: initial).id == "first")
        #expect(try PlaybackPreparationPolicy.resolveSource(in: [.init(id: "nil-tag"), .init(id: "initial")], initial: .init(id: "initial"))
            .id == "nil-tag")
    }

    @Test
    func `live and placeholder sources exclude explicit source ID and preserve selections`() {
        let profile = DeviceProfile(name: "profile")
        let source = MediaSourceInfo(id: "source", liveStreamID: "live")
        let normal = PlaybackPreparationPolicy.info(
            item: .init(id: "item"),
            initial: source,
            userID: "exact",
            profile: profile,
            maxBitrate: 8_000_000,
            audio: 2,
            subtitle: -1
        )
        #expect(normal.mediaSourceID == "source" && normal.userID == "exact" && normal.isAutoOpenLiveStream == true)
        #expect(normal.audioStreamIndex == 2 && normal.subtitleStreamIndex == -1 && normal.liveStreamID == "live" && normal.deviceProfile?
            .name == "profile" && normal.maxStreamingBitrate == 8_000_000)
        let live = PlaybackPreparationPolicy.info(
            item: .init(channelType: .tv, id: "item"),
            initial: source,
            userID: "exact",
            profile: profile,
            maxBitrate: 1,
            audio: nil,
            subtitle: nil
        )
        let placeholder = PlaybackPreparationPolicy.info(
            item: .init(id: "item"),
            initial: .init(id: "source", type: .placeholder),
            userID: "exact",
            profile: profile,
            maxBitrate: 1,
            audio: nil,
            subtitle: nil
        )
        #expect(live.mediaSourceID == nil && placeholder.mediaSourceID == nil)
    }
}

@Suite("Scoped playback preparation requests")
@MainActor
struct PreparationClientTests {
    private func client(_ sender: Sender, urls: URLResolver = URLResolver(), binding: Binding? = nil) -> PlaybackPreparationClient {
        .init(executor: .init(sender: sender, isCurrent: { binding?.current ?? true }), urls: urls, userID: "exact-user")
    }

    @Test
    func `posted info keeps exact item payload and runtime from resolved source`() async throws {
        let sender = Sender(), urls = URLResolver()
        sender
            .responses["/Items/item/PlaybackInfo"] = Data(
                #"{"MediaSources":[{"Id":"source","ETag":"tag","RunTimeTicks":999}],"PlaySessionId":"session"}"#
                    .utf8
            )
        let result = try await client(sender, urls: urls).prepare(
            item: .init(id: "item", mediaType: .video, runTimeTicks: 111),
            initial: .init(eTag: "tag", id: "source"),
            profile: .init(name: "profile"),
            maxBitrate: 8_000_000,
            audio: 3,
            subtitle: 4
        )
        #expect(result.item.runTimeTicks == 999 && result.source.id == "source" && result.playSessionID == "session" && result.url
            .absoluteString == "http://example.invalid/static")
        #expect(sender.calls.count == 1 && sender.calls[0].path == "/Items/item/PlaybackInfo" && sender.calls[0].method == "POST")
        let body = try object(#require(sender.calls[0].body))
        #expect(body["UserId"] as? String == "exact-user" && body["MediaSourceId"] as? String == "source")
        #expect(body["AudioStreamIndex"] as? Int == 3 && body["SubtitleStreamIndex"] as? Int == 4 && body["MaxStreamingBitrate"] as? Int ==
            8_000_000)
        #expect(urls.requests.count == 1 && urls.paths.isEmpty)
    }

    @Test
    func `missing session and missing response source cannot produce playback`() async {
        for body in [#"{"MediaSources":[{"Id":"source"}]}"#, #"{"PlaySessionId":"session"}"#] {
            let sender = Sender()
            sender.responses["/Items/item/PlaybackInfo"] = Data(body.utf8)
            await #expect(throws: PlaybackPreparationError.self) { try await client(sender).prepare(
                item: .init(id: "item"),
                initial: .init(id: "source"),
                profile: .init(),
                maxBitrate: 1,
                audio: nil,
                subtitle: nil
            ) }
        }
    }

    @Test
    func `stream URL retains transcode precedence static query and non video path`() throws {
        let sender = Sender(), urls = URLResolver()
        let c = client(sender, urls: urls)
        let transcode = try c.streamURL(
            item: .init(id: "item", mediaType: .video),
            source: .init(transcodingURL: "/transcode?synthetic=1"),
            sessionID: "session"
        )
        #expect(transcode.absoluteString == "http://example.invalid/transcode?synthetic=1" && urls.requests.isEmpty)
        _ = try c.streamURL(
            item: .init(etag: "item-tag", id: "item", mediaType: .video),
            source: .init(liveStreamID: "live"),
            sessionID: "session"
        )
        let request = try #require(urls.requests.first)
        let q = Dictionary(uniqueKeysWithValues: (request.query ?? []).compactMap { k, v in v.map { (k, $0) } })
        #expect(request.url?.path == "/Videos/item/stream")
        #expect(q["static"] == "true" && q["tag"] == "item-tag" && q["playSessionId"] == "session" && q["mediaSourceId"] == "item" &&
            q["liveStreamId"] == "live")
        #expect(try c.streamURL(
            item: .init(id: "audio", mediaType: .audio),
            source: .init(path: "https://example.invalid/audio"),
            sessionID: "session"
        ).absoluteString == "https://example.invalid/audio")
        #expect(sender.calls.isEmpty)
    }

    @Test
    func `invalid UR ls and missing identity remain typed errors without IO`() {
        let sender = Sender(), urls = URLResolver()
        urls.fail = true
        let c = client(sender, urls: urls)
        #expect(throws: PlaybackPreparationError.self) { try c.streamURL(item: .init(), source: .init(), sessionID: "session") }
        #expect(throws: PlaybackPreparationError.self) { try c.streamURL(
            item: .init(id: "item", mediaType: .video),
            source: .init(),
            sessionID: "session"
        ) }
        #expect(throws: PlaybackPreparationError.self) { try c.streamURL(item: .init(id: "item"), source: .init(), sessionID: "session") }
        #expect(sender.calls.isEmpty)
    }

    @Test
    func `metadata and preview reads keep exact account and selected source`() async throws {
        let sender = Sender()
        let c = client(sender)
        sender.responses["/Items/item"] = Data(#"{"Id":"item"}"#.utf8)
        let bytes = Data([1, 2, 3])
        sender.responses["/Videos/item/Trickplay/320/1.jpg"] = try JSONEncoder().encode(bytes)
        sender.responses["/image"] = try JSONEncoder().encode(bytes)
        #expect(try await c.item(id: "item").id == "item")
        #expect(sender.calls[0].query == ["userId": "exact-user"])
        _ = try await c.trickplayImage(itemID: "item", width: 320, index: 1, sourceID: "selected-source")
        _ = try await c.image(url: #require(URL(string: "http://example.invalid/image")))
        #expect(sender.calls[1].path == "/Videos/item/Trickplay/320/1.jpg" && sender.calls[1].query["mediaSourceId"] == "selected-source")
        #expect(sender.calls[2].path == "/image" && sender.calls.allSatisfy { $0.method == "GET" })
    }

    @Test
    func `account replacement rejects late metadata post and bitrate success or error`() async {
        for path in ["/Items/item", "/Items/item/PlaybackInfo", "/Playback/BitrateTest"] {
            let sender = Sender(), binding = Binding(), gate = Gate()
            sender.gate = gate
            sender.failure = true
            let c = client(sender, binding: binding)
            let task = Task {
                switch path {
                case "/Items/item": _ = try await c.item(id: "item")
                case "/Items/item/PlaybackInfo": _ = try await c.prepare(
                        item: .init(id: "item"),
                        initial: .init(),
                        profile: .init(),
                        maxBitrate: 1,
                        audio: nil,
                        subtitle: nil
                    )
                default: _ = try await c.bitrateBytes(size: 1024)
                }
            }
            await settle { gate.continuation != nil }
            binding.current = false
            gate.finish()
            await #expect(throws: CancellationError.self) { try await task.value }
            #expect(sender.calls.count == 1)
        }
    }

    @Test
    func `already expired preparation does no request or URL construction`() async {
        let sender = Sender(), binding = Binding(), urls = URLResolver()
        binding.current = false
        await #expect(throws: CancellationError.self) { try await client(sender, urls: urls, binding: binding).prepare(
            item: .init(id: "item"),
            initial: .init(),
            profile: .init(),
            maxBitrate: 1,
            audio: nil,
            subtitle: nil
        ) }
        #expect(sender.calls.isEmpty && urls.paths.isEmpty && urls.requests.isEmpty)
    }

    @Test
    func `runtime fallback and exact bitrate payload are preserved`() async throws {
        let sender = Sender()
        let c = client(sender)
        sender.responses["/Items/item/PlaybackInfo"] = Data(#"{"MediaSources":[{"Id":"source"}],"PlaySessionId":"session"}"#.utf8)
        sender.responses["/Playback/BitrateTest"] = try JSONEncoder().encode(Data([1, 2, 3, 4]))
        let result = try await c.prepare(
            item: .init(id: "item", mediaType: .video, runTimeTicks: 111),
            initial: .init(id: "source"),
            profile: .init(),
            maxBitrate: 1,
            audio: nil,
            subtitle: nil
        )
        #expect(result.item.runTimeTicks == 111)
        #expect(try await c.bitrateBytes(size: 4096) == Data([1, 2, 3, 4]))
        #expect(sender.calls[1].path == "/Playback/BitrateTest" && sender.calls[1].query == ["size": "4096"])
    }

    @Test
    func `fresh metadata cannot substitute different playback identity`() async {
        let sender = Sender()
        sender.responses["/Items/item"] = Data(#"{"Id":"other"}"#.utf8)
        await #expect(throws: PlaybackPreparationError.self) { try await client(sender).item(id: "item") }
        #expect(sender.calls.count == 1 && sender.calls[0].method == "GET")
    }
}
