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
import KidsDomain
import Testing

private final class PerformanceEvents: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [KidsPerformanceEvent] = []
    func append(_ event: KidsPerformanceEvent) {
        lock.lock()
        storage.append(event)
        lock.unlock()
    }

    var events: [KidsPerformanceEvent] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }
}

@Test
func `disabled profiling does not create storage or emit events`() {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let events = PerformanceEvents()
    let recorder = KidsPerformanceRecorder(enabled: false, directory: dir, sink: events.append)
    #expect(recorder.begin(.playback) == nil)
    recorder.flush()
    #expect(events.events.isEmpty)
    #expect(!FileManager.default.fileExists(atPath: dir.path))
}

@Test
func `performance records are concurrent monotonic deduplicated and retain trace ancestry`() async throws {
    let events = PerformanceEvents()
    let recorder = KidsPerformanceRecorder(enabled: true, sink: events.append)
    let parent = try #require(recorder.begin(.playback, variant: .ordered))
    let child = try #require(recorder.begin(.http, endpoint: .ancestors, parent: parent))
    await withTaskGroup(of: Void.self) { group in
        for _ in 0 ..< 100 {
            group.addTask { child.once(.firstInput)
                child.finish()
                child.mark(.network)
            }
        }
    }
    recorder.flush()
    let samples = events.events.filter { $0.traceID == child.id }
    #expect(samples.filter { $0.phase == .firstInput }.count == 1)
    #expect(samples.filter { $0.phase == .end }.count == 1)
    #expect(samples.filter { $0.phase == .network }.count == 100)
    #expect(samples.allSatisfy { $0.parentID == parent.id && $0.elapsedMS >= 0 && $0.uptimeMS > 0 && $0.unixMS > 0 })
    let inherited = await KidsPerformance.$current.withValue(parent) { await Task { KidsPerformance.current?.id }.value }
    #expect(inherited == parent.id)
}

@Test
func `diagnostics redact arbitrary measurement keys and reject nonfinite values`() throws {
    let events = PerformanceEvents()
    let recorder = KidsPerformanceRecorder(enabled: true, sink: events.append)
    let span = try #require(recorder.begin(.http, endpoint: .artwork))
    span.finish(values: ["bytes": 123, "ttfb_ms": .nan, "https://host/?token=private-secret": 1])
    recorder.flush()
    let event = try #require(events.events.last)
    #expect(event.values == ["bytes": 123])
    let json = try String(decoding: JSONEncoder().encode(event), as: UTF8.self)
    #expect(!json.contains("private-secret"))
    #expect(!json.contains("https://"))
}

@Test
func `profiling files have complete JSON lines and a finite recording cap`() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: dir) }
    let recorder = KidsPerformanceRecorder(enabled: true, directory: dir, maxBytes: 4096, sink: { _ in })
    let span = try #require(recorder.begin(.artwork))
    for _ in 0 ..< 100 {
        span.mark(.network, values: ["bytes": 123])
    }
    recorder.flush()
    let data = try Data(contentsOf: #require(recorder.fileURL))
    #expect(data.count <= 4096 && !data.isEmpty)
    #expect(data.last == 10)
    for line in data.split(separator: 10) {
        _ = try JSONDecoder().decode(KidsPerformanceEvent.self, from: Data(line))
    }
}

@Test
func `performance failures use fixed categories and never serialize error descriptions`() throws {
    struct PrivateFailure: LocalizedError {
        let errorDescription: String? = "https://server/media?token=private-secret"
    }
    let events = PerformanceEvents()
    let recorder = KidsPerformanceRecorder(enabled: true, sink: events.append)
    try #require(recorder.begin(.episodes)).finish(error: KidsContractError.ambiguousEpisodes)
    try #require(recorder.begin(.http)).finish(error: PrivateFailure())
    recorder.flush()
    let failures = events.events.filter { $0.phase == .end }
    #expect(failures.map { $0.values["failure_code"] } == [9, 0])
    #expect(failures.allSatisfy { $0.outcome == .failure })
    let json = try String(decoding: JSONEncoder().encode(failures), as: UTF8.self)
    #expect(!json.contains("private-secret"))
    #expect(!json.contains("https://"))
    #expect(KidsPerformanceCodec("h264") == .h264)
    #expect(KidsPerformanceCodec("HEVC") == .hevc)
    #expect(KidsPerformanceCodec("arbitrary-server-string") == .other)
}
