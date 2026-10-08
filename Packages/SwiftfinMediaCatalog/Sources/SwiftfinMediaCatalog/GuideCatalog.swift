//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation
import JellyfinAPI

/// Guide calendar/time rules take one explicit clock and calendar snapshot.
public struct GuideTimeline: Sendable {
    public let calendar: Calendar
    public let minimumInterval: TimeInterval
    public init(minimumInterval: TimeInterval = 12 * 60 * 60, calendar: Calendar = .current) {
        self.minimumInterval = minimumInterval
        self.calendar = calendar
    }

    public func availableDates(at now: Date) -> [Date] {
        let today = calendar.startOfDay(for: now)
        return (0 ..< 7).compactMap { calendar.date(byAdding: .day, value: $0, to: today) }
    }

    public func endDate(startingAt start: Date) -> Date {
        let spanEnd = start.addingTimeInterval(minimumInterval)
        guard let nextDay = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: start)) else { return spanEnd }
        return max(spanEnd, nextDay)
    }

    public func defaultStartDate(at now: Date) -> Date {
        let components = calendar.dateComponents([.minute, .second, .nanosecond], from: now)
        let elapsed = TimeInterval(((components.minute ?? 0) % 30) * 60 + (components.second ?? 0))
            + TimeInterval(components.nanosecond ?? 0) / 1_000_000_000
        return now.addingTimeInterval(-elapsed)
    }

    public func selectedStartDate(_ date: Date, now: Date) -> Date {
        calendar.isDate(date, inSameDayAs: now) ? defaultStartDate(at: now) : calendar.startOfDay(for: date)
    }

    public func refreshedStartDate(_ start: Date, now: Date) -> Date {
        calendar.isDate(start, inSameDayAs: now) || start < calendar.startOfDay(for: now) ? defaultStartDate(at: now) : start
    }

    public func needsRebase(start: Date, now: Date) -> Bool {
        now >= endDate(startingAt: start) || start < calendar.startOfDay(for: now)
    }
}

public struct GuidePage: Sendable {
    public let channels: [BaseItemDto]
    public let programs: [String: [ProgramBlock]]
    public let nextOffset: Int
    public let hasNextPage: Bool
}

/// One atomic guide result: publication cannot expose a new channel with an old
/// program table/cursor when UI observation submits a reentrant request.
public struct GuideSnapshot: Equatable, Sendable {
    public let startDate: Date
    public let channels: [BaseItemDto]
    public let programs: [String: [ProgramBlock]]
    public let nextOffset: Int
    public let hasNextPage: Bool
    public let revision: Int
    public init(startDate: Date) {
        self.startDate = startDate
        channels = []
        programs = [:]
        nextOffset = 0
        hasNextPage = true
        revision = 0
    }

    private init(
        startDate: Date,
        channels: [BaseItemDto],
        programs: [String: [ProgramBlock]],
        nextOffset: Int,
        hasNextPage: Bool,
        revision: Int
    ) {
        self.startDate = startDate
        self.channels = channels
        self.programs = programs
        self.nextOffset = nextOffset
        self.hasNextPage = hasNextPage
        self.revision = revision
    }

    public func applying(_ page: GuidePage, startDate: Date, replacing: Bool) -> Self {
        .init(
            startDate: startDate,
            channels: replacing ? page.channels : channels + page.channels,
            programs: replacing ? page.programs : programs.merging(page.programs) { _, new in new },
            nextOffset: page.nextOffset,
            hasNextPage: page.hasNextPage,
            revision: revision &+ 1
        )
    }
}

public enum GuideReadError: Error { case invalidCursor }

public extension MediaCatalogClient {
    /// Raw server rows advance the cursor, even when eligibility/deduplication
    /// removes displayed channels. Program grouping preserves the installed rules.
    func guidePage(
        offset: Int,
        limit: Int,
        startDate: Date,
        endDate: Date,
        excluding channelIDs: Set<String> = [],
        validate: @MainActor @Sendable () throws -> Void = {}
    ) async throws -> GuidePage {
        func check() throws {
            try checkBinding()
            try validate()
            try checkBinding()
        }
        try check()
        guard offset >= 0, limit > 0 else { throw GuideReadError.invalidCursor }
        do {
            let rows = try await page(.channels, at: .init(offset: offset, limit: limit)).items
            try check()
            var seen = channelIDs
            let channels = rows.filter { row in
                guard let id = row.id, !id.isEmpty, id.trimmingCharacters(in: .whitespacesAndNewlines) == id else { return false }
                return seen.insert(id).inserted
            }
            let next = offset.addingReportingOverflow(rows.count)
            guard !next.overflow else { throw GuideReadError.invalidCursor }
            let ids = channels.compactMap(\.id)
            let fetched = ids.isEmpty ? [] : try await programs(channelIDs: ids, startDate: startDate, endDate: endDate)
            try check()
            let grouped = fetched.reduce(into: [String: [BaseItemDto]]()) { result, program in
                guard let id = program.channelID, !id.isEmpty, id.trimmingCharacters(in: .whitespacesAndNewlines) == id else { return }
                result[id, default: []].append(program)
            }.mapValues { $0.programBlocks(startDate: startDate, endDate: endDate) }
            try check()
            return .init(channels: channels, programs: grouped, nextOffset: next.partialValue, hasNextPage: rows.count >= limit)
        } catch { try check()
            throw error
        }
    }
}
