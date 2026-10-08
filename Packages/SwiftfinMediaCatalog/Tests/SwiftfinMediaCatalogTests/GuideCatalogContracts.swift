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
import SwiftfinMediaCatalog
import Testing

@MainActor
private final class GuideReader: MediaCatalogReading {
    var paths: [String] = []
    var queries: [[String: String]] = []
    var responses: [String: String] = [:]
    var waitPath: String?
    var gate: CheckedContinuation<Void, Never>?
    var failure = false
    func read<Value: Decodable & Sendable>(_ request: Request<Value>) async throws -> Value {
        #expect(request.method == .get && request.body == nil)
        let path = request.url?.path ?? ""
        paths.append(path)
        queries.append(Dictionary(
            grouping: (request.query ?? []).compactMap { key, value in value.map { (key, $0) } },
            by: { $0.0 }
        ).mapValues { $0.map(\.1).joined(separator: ",") })
        if path == waitPath {
            await withCheckedContinuation { gate = $0 }
        }
        if failure {
            throw URLError(.notConnectedToInternet)
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(Value.self, from: Data((responses[path] ?? "{}").utf8))
    }

    func release() {
        gate?.resume()
        gate = nil
    }
}

@MainActor
private final class GuideBinding { var current = true }
private func guideDate(_ text: String) -> Date {
    ISO8601DateFormatter().date(from: text)!
}

private func guideCalendar(_ zone: String = "UTC") -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: zone)!
    return calendar
}

@MainActor
private func guideSettle(_ condition: () -> Bool) async throws {
    for _ in 0 ..< 2000 {
        if condition() {
            return
        }
        await Task.yield()
    }
    try #require(condition())
}

@Suite(.serialized) @MainActor
struct GuideCatalogContracts {
    @Test
    func `half-hour rounding and explicit-day selection retain seconds and midnight rules`() {
        let timeline = GuideTimeline(calendar: guideCalendar())
        let now = guideDate("2027-01-15T13:47:19Z").addingTimeInterval(0.375)
        #expect(abs(timeline.defaultStartDate(at: now).timeIntervalSince(guideDate("2027-01-15T13:30:00Z"))) < 0.000001)
        #expect(timeline.selectedStartDate(guideDate("2027-01-15T01:00:00Z"), now: now) == timeline.defaultStartDate(at: now))
        #expect(timeline.selectedStartDate(guideDate("2027-01-17T15:00:00Z"), now: now) == guideDate("2027-01-17T00:00:00Z"))
        #expect(timeline.refreshedStartDate(guideDate("2027-01-14T00:00:00Z"), now: now) == timeline.defaultStartDate(at: now))
        #expect(timeline.refreshedStartDate(guideDate("2027-01-17T00:00:00Z"), now: now) == guideDate("2027-01-17T00:00:00Z"))
        #expect(timeline.availableDates(at: now).count == 7)
    }

    @Test
    func `minimum span next calendar day and strict rebase survive daylight saving changes`() {
        let timeline = GuideTimeline(calendar: guideCalendar("America/Los_Angeles"))
        let start = guideDate("2026-11-01T07:00:00Z")
        #expect(timeline.endDate(startingAt: start).timeIntervalSince(start) == 25 * 60 * 60)
        #expect(!timeline.needsRebase(start: start, now: start.addingTimeInterval(3600)))
        #expect(timeline.needsRebase(start: start, now: timeline.endDate(startingAt: start)))
        let late = guideDate("2026-11-02T04:00:00Z")
        #expect(timeline.endDate(startingAt: late) == late.addingTimeInterval(12 * 60 * 60))
    }

    @Test
    func `guide cursor counts raw channels while identity filtering and grouping preserve first order`() async throws {
        let reader = GuideReader()
        reader.responses["/LiveTv/Channels"] = #"{"Items":[{"Id":"c","Name":"first"},{},{"Id":" "},{"Id":" padded"},{"Id":"c","Name":"duplicate"},{"Id":"d"}]}"#
        reader.responses["/LiveTv/Programs"] = #"{"Items":[{"Id":"one","ChannelId":"c","StartDate":"2027-01-15T00:00:00Z","EndDate":"2027-01-15T00:10:00Z"},{"Id":"two","ChannelId":"c","StartDate":"2027-01-15T00:10:00Z","EndDate":"2027-01-15T00:20:00Z"},{"Id":"bad","ChannelId":" "}]}"#
        let start = guideDate("2027-01-15T00:00:00Z"), end = start.addingTimeInterval(3600)
        let page = try await MediaCatalogClient(reader: reader, userID: "exact-user").guidePage(
            offset: 13,
            limit: 6,
            startDate: start,
            endDate: end
        )
        #expect(page.channels.map(\.id) == ["c", "d"] && page.channels.first?.name == "first")
        #expect(page.nextOffset == 19 && page.hasNextPage)
        #expect(page.programs["c"]?.first?.programs.map(\.id) == ["one", "two"] && page.programs[" "] == nil)
        #expect(reader.queries[0]["startIndex"] == "13" && reader.queries[0]["limit"] == "6")
        #expect(reader.queries[1]["channelIds"] == "c,d" && reader.queries[1]["userId"] == "exact-user")
        #expect(reader.queries[1]["enableImages"] == "false" && reader.queries[1]["sortBy"] == "StartDate")
    }

    @Test
    func `excluded duplicate and blank-only page skips program IO but advances raw offset`() async throws {
        let reader = GuideReader()
        reader.responses["/LiveTv/Channels"] = #"{"Items":[{"Id":"c"},{"Id":"c"},{"Id":" "}]}"#
        let start = guideDate("2027-01-15T00:00:00Z")
        let page = try await MediaCatalogClient(reader: reader, userID: "user").guidePage(
            offset: 0,
            limit: 3,
            startDate: start,
            endDate: start,
            excluding: ["c"]
        )
        #expect(page.channels.isEmpty && page.programs.isEmpty && page.nextOffset == 3 && page.hasNextPage)
        #expect(reader.paths == ["/LiveTv/Channels"])
    }

    @Test
    func `replaced scope after channels prevents program IO and stale ordinary errors are cancelled`() async throws {
        let reader = GuideReader(), binding = GuideBinding()
        reader.waitPath = "/LiveTv/Channels"
        reader.responses["/LiveTv/Channels"] = #"{"Items":[{"Id":"c"}]}"#
        let catalog = MediaCatalogClient(reader: reader, userID: "user"), start = guideDate("2027-01-15T00:00:00Z")
        let task = Task { try await catalog.guidePage(offset: 0, limit: 1, startDate: start, endDate: start, validate: {
            guard binding.current else { throw CancellationError() }
        }) }
        defer { task.cancel()
            reader.release()
        }
        try await guideSettle { reader.gate != nil }
        binding.current = false
        reader.failure = true
        reader.release()
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(reader.paths == ["/LiveTv/Channels"])
    }

    @Test
    func `atomic snapshots carry programs cursor and revision through replacement and append`() async throws {
        let reader = GuideReader()
        reader.responses["/LiveTv/Channels"] = #"{"Items":[{"Id":"c"}]}"#
        let start = guideDate("2027-01-15T00:00:00Z"), catalog = MediaCatalogClient(reader: reader, userID: "user")
        let first = try await catalog.guidePage(offset: 0, limit: 1, startDate: start, endDate: start.addingTimeInterval(3600))
        let initial = GuideSnapshot(startDate: start).applying(first, startDate: start, replacing: true)
        reader.responses["/LiveTv/Channels"] = #"{"Items":[{"Id":"d"}]}"#
        let next = try await catalog.guidePage(
            offset: 1,
            limit: 2,
            startDate: start,
            endDate: start.addingTimeInterval(3600),
            excluding: ["c"]
        )
        let merged = initial.applying(next, startDate: start, replacing: false)
        #expect(merged.channels.map(\.id) == ["c", "d"] && merged.nextOffset == 2 && !merged.hasNextPage && merged.revision == 2)
        let replaced = merged.applying(first, startDate: start.addingTimeInterval(86400), replacing: true)
        #expect(replaced.channels.map(\.id) == ["c"] && replaced.nextOffset == 1 && replaced.revision == 3)
    }
}
