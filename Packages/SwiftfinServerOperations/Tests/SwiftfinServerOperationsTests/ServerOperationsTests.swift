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
}

@MainActor
private final class Sender: JellyfinRequestSending {
    var calls: [Captured] = []
    var responses: [String: Data] = [:]
    var gate: Gate?
    var failure = false
    private func capture(_ request: Request<some Any>) throws {
        let pairs = (request.query ?? []).compactMap { k, v in v.map { (k, $0) } }
        try calls.append(.init(
            path: request.url?.path ?? "",
            method: request.method.rawValue,
            query: Dictionary(grouping: pairs, by: { $0.0 }).mapValues { $0.map(\.1).joined(separator: ",") },
            body: request.body.map { try JSONEncoder().encode($0) }
        ))
    }

    func value<Value: Decodable & Sendable>(for request: Request<Value>) async throws -> Value {
        try capture(request)
        if let gate {
            await gate.wait()
        }
        if failure {
            throw StubError.offline
        }
        let data = responses[request.url?.path ?? ""] ?? Data((String(describing: Value.self).hasPrefix("Array<") ? "[]" : "{}").utf8)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(Value.self, from: data)
    }

    func complete(_ request: Request<Void>) async throws {
        try capture(request)
        if let gate {
            await gate.wait()
        }
        if failure {
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

import SwiftfinServerOperations

@Suite("Server operation policies and transport")
@MainActor
struct ServerOperationsTests {
    private func client(_ sender: Sender) -> ServerOperationsClient {
        .init(executor: .init(sender: sender), deviceID: "current-device")
    }

    @Test
    func `activity preserves paging and optional fields`() async throws {
        let s = Sender()
        let c = client(s)
        _ = try await c.activity(offset: 20, limit: 15, hasUserID: true, minimumDate: Date(timeIntervalSince1970: 0))
        let q = try #require(s.calls.first).query
        #expect(q["startIndex"] == "20" && q["limit"] == "15" && q["hasUserId"] == "true" && q["minDate"] != nil)
        #expect(s.calls[0].method == "GET" && s.calls[0].body == nil)
    }

    @Test
    func `deleting devices protects current device and skips empty batch`() async throws {
        let s = Sender()
        let c = client(s)
        #expect(try await c.deleteDevices(ids: ["current-device"]).isEmpty)
        #expect(s.calls.isEmpty)
        let deleted = try await c.deleteDevices(ids: ["current-device", "b", "a"])
        #expect(deleted == ["a", "b"])
        #expect(s.calls.count == 1)
        #expect(s.calls[0].query["id"] == "a,b" && s.calls[0].method == "DELETE")
    }

    @Test
    func `expired binding cannot delete other devices`() async {
        let s = Sender()
        let c = ServerOperationsClient(executor: .init(sender: s, isCurrent: { false }), deviceID: "current")
        await #expect(throws: CancellationError.self) { try await c.deleteDevices(ids: ["other"]) }
        #expect(s.calls.isEmpty)
    }

    @Test
    func `key and device ordering preserve nil behavior`() {
        let keys = [AuthenticationInfo(appName: "z"), AuthenticationInfo(appName: "A"), AuthenticationInfo()]
        #expect(ServerOperationsPolicy.sortedKeys(keys).map(\.appName) == [nil, "A", "z"])
        let devices = [
            DeviceInfoDto(dateLastActivity: Date(timeIntervalSince1970: 1), id: "old"),
            DeviceInfoDto(id: "nil"),
            DeviceInfoDto(dateLastActivity: Date(timeIntervalSince1970: 2), id: "new")
        ]
        #expect(ServerOperationsPolicy.sortedDevices(devices).map(\.id) == ["nil", "new", "old"])
    }

    @Test
    func `session filter preserves missing dates and playback grouping`() {
        let now = Date(timeIntervalSince1970: 1000)
        let values = [
            SessionInfoDto(id: "old", lastActivityDate: .init(timeIntervalSince1970: 0)),
            SessionInfoDto(id: "no-date"),
            SessionInfoDto(id: "playing", lastActivityDate: now, nowPlayingItem: .init(name: "Show"))
        ]
        #expect(ServerOperationsPolicy.sessions(values, activeWithinSeconds: 50, filter: .all, now: now).map(\.id) == [
            "playing",
            "no-date"
        ])
        #expect(ServerOperationsPolicy.sessions(values, activeWithinSeconds: nil, filter: .active, now: now).map(\.id) == ["playing"])
        #expect(ServerOperationsPolicy.sessions(values, activeWithinSeconds: 50, filter: .inactive, now: now).map(\.id) == ["no-date"])
        #expect(!ServerOperationsPolicy.sessionPrecedes(values[1], values[1], now: now))
    }

    @Test
    func `task removal and trigger removal preserve unrelated entries`() {
        #expect(ServerOperationsPolicy.removedTaskIDs(existing: ["a", "b"], incoming: [.init(id: "b"), .init(id: "c")]) == ["a"])
        let a = TaskTriggerInfo(type: .dailyTrigger)
        let b = TaskTriggerInfo(type: .weeklyTrigger)
        #expect(ServerOperationsPolicy.triggers(removing: a, from: [a, b, a]) == [b])
    }

    @Test
    func `null key and device results do not clear existing presentation`() async throws {
        let s = Sender()
        let c = client(s)
        #expect(try await c.keys() == nil)
        #expect(try await c.devices() == nil)
    }

    @Test
    func `all existing operation routes use captured executor`() async throws {
        let s = Sender()
        let c = client(s)
        _ = try await c.logs()
        _ = try await c.activityItem(id: "item")
        _ = try await c.keys()
        _ = try await c.devices()
        _ = try await c.tasks()
        _ = try await c.sessions(activeWithinSeconds: 900)
        _ = try await c.backups()
        let backup = BackupManifestDto(
            backupEngineVersion: "1",
            dateCreated: .init(timeIntervalSince1970: 0),
            options: .init(),
            path: "/internal/backup.zip",
            serverVersion: "1"
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        s.responses["/Backup/Create"] = try encoder.encode(backup)
        let created = try await c.createBackup(options: .init())
        #expect(created.path == backup.path)
        try await c.createKey(name: "App")
        try await c.revokeKey(token: "synthetic")
        try await c.updateDevice(id: "device", options: .init(customName: "TV"))
        try await c.startTask(id: "task")
        try await c.stopTask(id: "task")
        try await c.updateTriggers(id: "task", triggers: [])
        try await c.restart()
        try await c.shutdown()
        try await c.restoreBackup(path: "/internal/backups/backup.zip")
        try await c.message(sessionID: "session", command: .init(text: "Hi"))
        try await c.playstate(sessionID: "session", command: .seek, position: 123)
        try await c.general(sessionID: "session", command: .volumeUp)
        try await c.play(
            sessionID: "session",
            command: .playNow,
            itemIDs: ["item"],
            position: 7,
            mediaSourceID: "source",
            audioIndex: 2,
            subtitleIndex: 3,
            startIndex: 1
        )
        #expect(s.calls.count == 21)
        #expect(s.calls.first?.path == "/System/Logs" && s.calls[0].method == "GET")
        let restore = try #require(s.calls.first { $0.path == "/Backup/Restore" })
        let body = try #require(restore.body)
        let object = try JSONSerialization.jsonObject(with: body) as? [String: String]
        #expect(object?["ArchiveFileName"] == "backup.zip")
        #expect(s.calls.contains { $0.query["seekPositionTicks"] == "123" })
    }
}
