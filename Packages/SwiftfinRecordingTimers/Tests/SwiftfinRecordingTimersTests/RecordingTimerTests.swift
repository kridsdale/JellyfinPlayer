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
    var gatePath: String?
    private func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private func capture(_ request: Request<some Any>) throws {
        let pairs = (request.query ?? []).compactMap { k, v in v.map { (k, $0) } }
        try calls.append(.init(
            path: request.url?.path ?? "",
            method: request.method.rawValue,
            query: Dictionary(grouping: pairs, by: { $0.0 }).mapValues { $0.map(\.1).joined(separator: ",") },
            body: request.body.map { try encoder().encode($0) }
        ))
    }

    func value<Value: Decodable & Sendable>(for request: Request<Value>) async throws -> Value {
        try capture(request)
        if let gate, gatePath == nil || gatePath == request.url?.path {
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
        if let gate, gatePath == nil || gatePath == request.url?.path {
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

import SwiftfinRecordingTimers

private let instant = Date(timeIntervalSince1970: 1_800_000_000)
private func decode<T: Decodable>(_ text: String, _ type: T.Type = T.self) throws -> T {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return try decoder.decode(type, from: Data(text.utf8))
}

@MainActor
private final class Permission { var allowed = true }

@Suite("Recording timer ownership")
@MainActor
struct RecordingTimerTests {
    private func client(
        _ sender: Sender,
        item: BaseItemDto = .init(id: "program", type: .program),
        binding: Binding? = nil,
        permission: Permission? = nil
    ) -> RecordingTimersClient {
        .init(
            executor: .init(sender: sender, isCurrent: { binding?.current ?? true }),
            userID: "exact-user",
            item: item,
            permission: { permission?.allowed ?? true },
            now: { instant }
        )
    }

    private func state(series: Bool = false) throws -> RecordingTimerSnapshot {
        let program = try decode(
            #"{"Id":"program","Name":"Episode","Type":"Program","IsSeries":true,"ChannelId":"channel","StartDate":"2027-01-15T00:00:00Z","EndDate":"2027-01-16T00:00:00Z"}"#,
            BaseItemDto.self
        )
        return .init(program: program, recordingTimer: nil, seriesRecordingTimer: nil)
    }

    @Test(arguments: [BaseItemKind.channel, .liveTvChannel, .tvChannel])
    func `channels use exact user and only first airing program`(_ kind: BaseItemKind) async throws {
        let sender = Sender()
        sender.responses["/LiveTv/Programs"] = Data(#"{"Items":[{"Id":"first"},{"Id":"second"}]}"#.utf8)
        let result = try await client(sender, item: .init(id: "channel", type: kind)).snapshot()
        #expect(result.program?.id == "first" && result.recordingTimer == nil && result.seriesRecordingTimer == nil)
        #expect(sender.calls.count == 1)
        #expect(sender.calls[0].query == ["channelIds": "channel", "isAiring": "true", "limit": "1", "userId": "exact-user"])
    }

    @Test(arguments: [BaseItemKind.program, .liveTvProgram, .tvProgram])
    func `programs resolve scheduled and direct series timer`(_ kind: BaseItemKind) async throws {
        let sender = Sender()
        sender.responses["/LiveTv/Programs/program"] = Data(#"{"Id":"resolved","TimerId":"timer","SeriesTimerId":"series"}"#.utf8)
        sender.responses["/LiveTv/Timers/timer"] = Data(#"{"Id":"timer","Status":"InProgress"}"#.utf8)
        sender.responses["/LiveTv/SeriesTimers/series"] = Data(#"{"Id":"series"}"#.utf8)
        let result = try await client(sender, item: .init(id: "program", type: kind)).snapshot()
        #expect(result.program?.id == "resolved" && result.recordingTimer?.id == "timer" && result.seriesRecordingTimer?.id == "series")
        #expect(sender.calls.map(\.path) == ["/LiveTv/Programs/program", "/LiveTv/Timers/timer", "/LiveTv/SeriesTimers/series"])
        #expect(sender.calls[0].query == ["userId": "exact-user"])
    }

    @Test
    func `cancelled timer is excluded and series fallback matches exact program`() async throws {
        let sender = Sender()
        sender.responses["/LiveTv/Programs/program"] = Data(#"{"Id":"program","TimerId":"timer","IsSeries":true}"#.utf8)
        sender.responses["/LiveTv/Timers/timer"] = Data(#"{"Id":"timer","Status":"Cancelled"}"#.utf8)
        sender
            .responses["/LiveTv/SeriesTimers"] = Data(
                #"{"Items":[{"Id":"wrong","ProgramId":"other"},{"Id":"correct","ProgramId":"program"},{"Id":"later","ProgramId":"program"}]}"#
                    .utf8
            )
        let result = try await client(sender).snapshot()
        #expect(result.recordingTimer == nil && result.seriesRecordingTimer?.id == "correct")
    }

    @Test
    func `missing identity unsupported type and empty airing response do no further IO`() async throws {
        for item in [BaseItemDto(type: .program), .init(id: "movie", type: .movie)] {
            let sender = Sender()
            let result = try await client(sender, item: item).snapshot()
            #expect(result.program == nil && sender.calls.isEmpty)
        }
        let sender = Sender()
        let result = try await client(sender, item: .init(id: "empty", type: .channel)).snapshot()
        #expect(result.program == nil && sender.calls.count == 1)
    }

    @Test
    func `recordability requires permission type and strict future end`() {
        #expect(RecordingTimerPolicy.canRecord(.init(type: .channel), permitted: true, now: instant))
        #expect(!RecordingTimerPolicy.canRecord(.init(type: .channel), permitted: false, now: instant))
        #expect(!RecordingTimerPolicy.canRecord(.init(type: .movie), permitted: true, now: instant))
        for kind in [BaseItemKind.program, .liveTvProgram, .tvProgram] {
            #expect(!RecordingTimerPolicy.canRecord(.init(type: kind), permitted: true, now: instant))
            #expect(!RecordingTimerPolicy.canRecord(.init(endDate: instant, type: kind), permitted: true, now: instant))
            #expect(RecordingTimerPolicy.canRecord(
                .init(endDate: instant.addingTimeInterval(1), type: kind),
                permitted: true,
                now: instant
            ))
        }
    }

    @Test
    func `cancellation and updates preserve routes and selected payloads`() async throws {
        let sender = Sender()
        let c = client(sender)
        let program = try state().program
        #expect(try await c.toggleRecording(.init(program: program, recordingTimer: .init(id: "one"), seriesRecordingTimer: nil)))
        #expect(try await c.toggleSeriesRecording(.init(program: program, recordingTimer: nil, seriesRecordingTimer: .init(id: "two"))))
        try await c.update(TimerInfoDto(id: "three", name: "changed", postPaddingSeconds: 7))
        try await c.update(SeriesTimerInfoDto(id: "four", isRecordAnyChannel: true, name: "changed series"))
        #expect(sender.calls.map(\.path) == [
            "/LiveTv/Timers/one",
            "/LiveTv/SeriesTimers/two",
            "/LiveTv/Timers/three",
            "/LiveTv/SeriesTimers/four"
        ])
        #expect(sender.calls.map(\.method) == ["DELETE", "DELETE", "POST", "POST"])
        let body = try decode(String(decoding: #require(sender.calls[2].body), as: UTF8.self), TimerInfoDto.self)
        #expect(body.id == "three" && body.postPaddingSeconds == 7)
    }

    @Test
    func `default template retains overrides and program fallbacks`() async throws {
        let sender = Sender()
        sender
            .responses["/LiveTv/Timers/Defaults"] = Data(
                #"{"Name":"Server name","ExternalChannelId":"external-c","ExternalProgramId":"external-p","IsPostPaddingRequired":true,"IsPrePaddingRequired":false,"KeepUntil":"UntilDeleted","Overview":"Overview","PostPaddingSeconds":12,"PrePaddingSeconds":5,"Priority":9,"ServerId":"server","ServiceName":"service"}"#
                    .utf8
            )
        #expect(try await client(sender).toggleRecording(state()))
        #expect(sender.calls.map(\.path) == ["/LiveTv/Timers/Defaults", "/LiveTv/Timers"])
        #expect(sender.calls[0].query == ["programId": "program"])
        let body = try decode(String(decoding: #require(sender.calls[1].body), as: UTF8.self), TimerInfoDto.self)
        let program = try #require(state().program)
        #expect(body.name == "Server name" && body.channelID == "channel" && body.programID == "program")
        #expect(body.startDate == program.startDate && body.endDate == program.endDate)
        #expect(body.externalChannelID == "external-c" && body.externalProgramID == "external-p")
        #expect(body.isPostPaddingRequired == true && body.isPrePaddingRequired == false)
        #expect(body.keepUntil == .untilDeleted && body.overview == "Overview" && body.postPaddingSeconds == 12 && body
            .prePaddingSeconds == 5)
        #expect(body.priority == 9 && body.serverID == "server" && body.serviceName == "service")
    }

    @Test
    func `series creation preserves full template without single timer fallback`() async throws {
        let sender = Sender()
        let template = #"{"Id":"template","ProgramId":"server-program","ChannelId":"server-channel","Name":"Server series","RecordAnyChannel":true,"RecordAnyTime":false,"RecordNewOnly":true,"SkipEpisodesInLibrary":true,"Days":["Monday","Friday"],"Priority":8}"#
        sender.responses["/LiveTv/Timers/Defaults"] = Data(template.utf8)
        #expect(try await client(sender).toggleSeriesRecording(state()))
        let sent = try #require(sender.calls[1].body)
        let expected = try JSONSerialization.jsonObject(with: Data(template.utf8)) as? NSDictionary
        #expect(try JSONSerialization.jsonObject(with: sent) as? NSDictionary == expected)
        #expect(sender.calls[1].path == "/LiveTv/SeriesTimers" && sender.calls[1].method == "POST")
    }

    @Test
    func `missing programs I ds and permission do not issue commands`() async throws {
        let sender = Sender()
        let permission = Permission()
        permission.allowed = false
        let c = client(sender, permission: permission)
        #expect(try await !(c.toggleRecording(.init(program: nil, recordingTimer: nil, seriesRecordingTimer: nil))))
        #expect(try await !(c.toggleRecording(state())))
        #expect(try await !(c.toggleSeriesRecording(state())))
        try await c.update(TimerInfoDto())
        try await c.update(SeriesTimerInfoDto())
        #expect(sender.calls.isEmpty)
    }

    @Test
    func `expired binding before IO and late response reject further stages`() async throws {
        let sender = Sender()
        let binding = Binding()
        binding.current = false
        let c = client(sender, binding: binding)
        await #expect(throws: CancellationError.self) { try await c.snapshot() }
        #expect(sender.calls.isEmpty)
        binding.current = true
        let gate = Gate()
        sender.gate = gate
        sender.responses["/LiveTv/Programs/program"] = Data(#"{"Id":"program","TimerId":"timer"}"#.utf8)
        let task = Task { try await c.snapshot() }
        await settle { gate.continuation != nil }
        binding.current = false
        gate.finish()
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(sender.calls.count == 1)
    }

    @Test
    func `permission revoked during template read prevents both creations`() async throws {
        for series in [false, true] {
            let sender = Sender()
            let permission = Permission()
            let gate = Gate()
            sender.gate = gate
            sender.gatePath = "/LiveTv/Timers/Defaults"
            let c = client(sender, permission: permission)
            let initial = try state()
            let task = Task {
                if series {
                    return try await c.toggleSeriesRecording(initial)
                }
                return try await c.toggleRecording(initial)
            }
            await settle { gate.continuation != nil }
            permission.allowed = false
            gate.finish()
            #expect(try await !(task.value))
            #expect(sender.calls.count == 1 && sender.calls[0].method == "GET")
        }
    }

    @Test
    func `cancelled wait and obsolete errors become cancellation`() async throws {
        for cancelled in [false, true] {
            let sender = Sender()
            let gate = Gate()
            let binding = Binding()
            sender.gate = gate
            sender.failure = true
            let c = client(sender, binding: binding)
            let task = Task { try await c.snapshot() }
            await settle { gate.continuation != nil }
            if cancelled {
                task.cancel()
            } else {
                binding.current = false
            }
            gate.finish()
            await #expect(throws: CancellationError.self) { try await task.value }
            #expect(sender.calls.count == 1)
        }
    }

    @Test
    func `current transport errors remain visible`() async {
        let sender = Sender()
        sender.failure = true
        await #expect(throws: StubError.self) { try await client(sender).snapshot() }
    }

    @Test
    func `editor update emits change before reloading and preserves the submitted payload`() async throws {
        let sender = Sender()
        sender.responses["/LiveTv/Programs/program"] = Data(#"{"Id":"program","Name":"Reloaded"}"#.utf8)
        let editor = RecordingTimerEditor(client: client(sender))
        var events: [String] = []
        try await editor.edit(.update(.init(id: "timer", name: "submitted")), publish: { state in
            events.append(state.program?.name ?? "nil")
        }, changed: { events.append("changed") })
        #expect(events == ["changed", "Reloaded"])
        #expect(sender.calls.map(\.path) == ["/LiveTv/Timers/timer", "/LiveTv/Programs/program"])
        #expect(sender.calls[0].method == "POST")
        let body = try #require(sender.calls[0].body)
        #expect(try JSONDecoder().decode(TimerInfoDto.self, from: body).name == "submitted")
    }

    @Test
    func `accepted edit keeps change receipt when subsequent reload fails`() async throws {
        let sender = Sender(), editor = RecordingTimerEditor(client: client(sender))
        var changes = 0, publications = 0
        await #expect(throws: StubError.self) { try await editor.edit(
            .update(.init(id: "timer")),
            publish: { _ in publications += 1 },
            changed: {
                changes += 1
                sender.failure = true
            }
        ) }
        #expect(changes == 1 && publications == 0 && sender.calls.map(\.path) == ["/LiveTv/Timers/timer", "/LiveTv/Programs/program"])
    }

    @Test
    func `change callback retirement stops reload after the accepted command`() async throws {
        let sender = Sender(), binding = Binding(), editor = RecordingTimerEditor(client: client(sender))
        await #expect(throws: CancellationError.self) { try await editor.edit(.update(.init(id: "timer")), validate: {
            guard binding.current else { throw CancellationError() }
        }, changed: { binding.current = false }) }
        #expect(sender.calls.map(\.path) == ["/LiveTv/Timers/timer"])
    }

    @Test
    func `toggle publishes its fresh initial snapshot and no-op creates no change receipt`() async throws {
        let sender = Sender(), editor = RecordingTimerEditor(client: client(sender, item: .init(id: "movie", type: .movie)))
        var publications = 0, changes = 0
        try await editor.edit(.toggleRecording, publish: { state in #expect(state.program == nil)
            publications += 1
        }, changed: { changes += 1 })
        #expect(publications == 1 && changes == 0 && sender.calls.isEmpty)
    }

    @Test
    func `queued edit drains accepted predecessor before a successor and refresh`() async throws {
        let sender = Sender(), gate = Gate(), editor = RecordingTimerEditor(client: client(sender))
        sender.gate = gate
        sender.gatePath = "/LiveTv/Timers/first"
        let first = Task { try await editor.edit(.update(.init(id: "first"))) }
        defer { first.cancel()
            gate.finish()
        }
        await settle { gate.continuation != nil }
        let second = Task { try await editor.edit(.update(.init(id: "second"))) }
        for _ in 0 ..< 20 {
            await Task.yield()
        }
        #expect(sender.calls.map(\.path) == ["/LiveTv/Timers/first"])
        gate.finish()
        try await first.value
        try await second.value
        #expect(sender.calls.map(\.path) == [
            "/LiveTv/Timers/first",
            "/LiveTv/Programs/program",
            "/LiveTv/Timers/second",
            "/LiveTv/Programs/program"
        ])
    }

    @Test
    func `retired editor admission and missing update identity perform no IO`() async throws {
        let sender = Sender(), editor = RecordingTimerEditor(client: client(sender))
        await #expect(throws: CancellationError.self) { try await editor.edit(.toggleRecording, validate: { throw CancellationError() }) }
        try await editor.edit(.update(.init()))
        try await editor.edit(.updateSeries(.init()))
        #expect(sender.calls.isEmpty)
    }
}
