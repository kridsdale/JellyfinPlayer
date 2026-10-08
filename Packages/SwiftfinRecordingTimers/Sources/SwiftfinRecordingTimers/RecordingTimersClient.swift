//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation
import JellyfinAPI
import SwiftfinMediaCatalog
import SwiftfinNetworking

public struct RecordingTimerSnapshot: Equatable, Sendable {
    public let program: BaseItemDto?
    public let recordingTimer: TimerInfoDto?
    public let seriesRecordingTimer: SeriesTimerInfoDto?
    public init(program: BaseItemDto?, recordingTimer: TimerInfoDto?, seriesRecordingTimer: SeriesTimerInfoDto?) {
        self.program = program
        self.recordingTimer = recordingTimer
        self.seriesRecordingTimer = seriesRecordingTimer
    }
}

public enum RecordingTimerPolicy {
    public static func canRecord(_ item: BaseItemDto, permitted: Bool, now: Date) -> Bool {
        guard permitted else { return false }
        switch item.type {
        case .channel, .liveTvChannel, .tvChannel: return true
        case .program, .liveTvProgram, .tvProgram: return (item.endDate ?? .distantPast) > now
        default: return false
        }
    }
}

@MainActor
public final class RecordingTimersClient {
    private let executor: AuthenticatedRequestExecutor
    private let userID: String
    private let item: BaseItemDto
    private let permission: @MainActor @Sendable () -> Bool
    private let now: @MainActor @Sendable () -> Date
    public init(
        executor: AuthenticatedRequestExecutor,
        userID: String,
        item: BaseItemDto,
        permission: @escaping @MainActor @Sendable () -> Bool,
        now: @escaping @MainActor @Sendable () -> Date = { .now }
    ) {
        self.executor = executor
        self.userID = userID
        self.item = item
        self.permission = permission
        self.now = now
    }

    public func checkBinding() throws {
        try executor.checkBinding()
    }

    public func snapshot() async throws -> RecordingTimerSnapshot {
        try checkBinding()
        let program = try await resolveProgram()
        let timer = try await currentRecordingTimer(for: program)
        let series = try await currentSeriesRecordingTimer(for: program)
        try checkBinding()
        return RecordingTimerSnapshot(program: program, recordingTimer: timer, seriesRecordingTimer: series)
    }

    @discardableResult
    public func toggleRecording(_ state: RecordingTimerSnapshot) async throws -> Bool {
        try checkBinding()
        guard let program = state.program else { return false }
        if let id = state.recordingTimer?.id {
            try await executor.complete(Paths.cancelTimer(timerID: id))
        } else {
            guard RecordingTimerPolicy.canRecord(program, permitted: permission(), now: now()) else { return false }
            guard try await createRecordingTimer(for: program) else { return false }
        }
        try checkBinding()
        return true
    }

    @discardableResult
    public func toggleSeriesRecording(_ state: RecordingTimerSnapshot) async throws -> Bool {
        try checkBinding()
        guard let program = state.program, program.isSeries == true else { return false }
        if let id = state.seriesRecordingTimer?.id {
            try await executor.complete(Paths.cancelSeriesTimer(timerID: id))
        } else {
            guard RecordingTimerPolicy.canRecord(program, permitted: permission(), now: now()) else { return false }
            guard try await createSeriesRecordingTimer(for: program) else { return false }
        }
        try checkBinding()
        return true
    }

    public func update(_ timer: TimerInfoDto) async throws {
        try checkBinding()
        guard let id = timer.id else { return }
        try await executor.complete(Paths.updateTimer(timerID: id, timer))
    }

    public func update(_ timer: SeriesTimerInfoDto) async throws {
        try checkBinding()
        guard let id = timer.id else { return }
        try await executor.complete(Paths.updateSeriesTimer(timerID: id, timer))
    }

    private func resolveProgram() async throws -> BaseItemDto? {
        guard let itemID = item.id else { return nil }

        switch item.type {
        case .channel, .liveTvChannel, .tvChannel:
            var parameters = Paths.GetLiveTvProgramsParameters()
            parameters.channelIDs = [itemID]
            parameters.isAiring = true
            parameters.limit = 1
            parameters.userID = userID

            let request = Paths.getLiveTvPrograms(parameters: parameters)
            let response = try await executor.value(for: request)
            return response.items?.first
        case .program, .liveTvProgram, .tvProgram:
            let request = Paths.getProgram(
                programID: itemID,
                userID: userID
            )
            return try await executor.value(for: request)
        default:
            return nil
        }
    }

    private func currentRecordingTimer(for program: BaseItemDto?) async throws -> TimerInfoDto? {
        guard let recordingTimerID = program?.timerID else { return nil }

        let request = Paths.getTimer(timerID: recordingTimerID)
        let recordingTimer = try await executor.value(for: request)
        return MediaCatalogPolicy.isScheduled(recordingTimer, now: now()) ? recordingTimer : nil
    }

    private func currentSeriesRecordingTimer(for program: BaseItemDto?) async throws -> SeriesTimerInfoDto? {
        guard let program else { return nil }

        if let seriesRecordingTimerID = program.seriesTimerID {
            let request = Paths.getSeriesTimer(timerID: seriesRecordingTimerID)
            return try await executor.value(for: request)
        }

        guard program.isSeries == true, let programID = program.id else { return nil }

        let request = Paths.getSeriesTimers()
        let response = try await executor.value(for: request)
        return response.items?.first { $0.programID == programID }
    }

    private func createRecordingTimer(for program: BaseItemDto) async throws -> Bool {
        guard let programID = program.id else { return false }

        let defaultsRequest = Paths.getDefaultTimer(programID: programID)
        let defaults = try await executor.value(for: defaultsRequest)
        guard RecordingTimerPolicy.canRecord(program, permitted: permission(), now: now()) else { return false }

        let recordingTimer = TimerInfoDto(
            channelID: defaults.channelID ?? program.channelID,
            endDate: defaults.endDate ?? program.endDate,
            externalChannelID: defaults.externalChannelID,
            externalProgramID: defaults.externalProgramID,
            isPostPaddingRequired: defaults.isPostPaddingRequired,
            isPrePaddingRequired: defaults.isPrePaddingRequired,
            keepUntil: defaults.keepUntil,
            name: defaults.name ?? program.name,
            overview: defaults.overview,
            postPaddingSeconds: defaults.postPaddingSeconds,
            prePaddingSeconds: defaults.prePaddingSeconds,
            priority: defaults.priority,
            programID: defaults.programID ?? programID,
            serverID: defaults.serverID,
            serviceName: defaults.serviceName,
            startDate: defaults.startDate ?? program.startDate
        )

        let request = Paths.createTimer(recordingTimer)
        try await executor.complete(request)
        return true
    }

    private func createSeriesRecordingTimer(for program: BaseItemDto) async throws -> Bool {
        guard let programID = program.id else { return false }

        let defaultsRequest = Paths.getDefaultTimer(programID: programID)
        let defaults = try await executor.value(for: defaultsRequest)
        guard RecordingTimerPolicy.canRecord(program, permitted: permission(), now: now()) else { return false }
        let request = Paths.createSeriesTimer(defaults)
        try await executor.complete(request)
        return true
    }
}
