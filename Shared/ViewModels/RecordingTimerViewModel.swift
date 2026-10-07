//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import CasePaths
import Foundation
import JellyfinAPI
import StatefulMacros
import SwiftfinRecordingTimers

@MainActor
@Stateful
final class RecordingTimerViewModel: ViewModel {

    @CasePathable
    enum Action {
        case refresh
        case toggleRecording
        case toggleSeriesRecording
        case updateRecordingTimer(TimerInfoDto)
        case updateSeriesRecordingTimer(SeriesTimerInfoDto)

        var transition: Transition {
            switch self {
            case .refresh:
                .background(.refreshing)
            case .toggleRecording, .toggleSeriesRecording, .updateRecordingTimer, .updateSeriesRecordingTimer:
                .background(.updating)
            }
        }
    }

    enum BackgroundState {
        case refreshing
        case updating
    }

    enum Event {
        case updated
    }

    enum State {
        case error
        case initial
    }

    @Published
    private(set) var program: BaseItemDto?
    @Published
    private(set) var recordingTimer: TimerInfoDto?
    @Published
    private(set) var seriesRecordingTimer: SeriesTimerInfoDto?

    private let item: BaseItemDto

    var canManageRecordings: Bool {
        (program?.canBeRecorded == true || recordingTimer != nil || seriesRecordingTimer != nil) &&
            !background.is(.refreshing) && !background.is(.updating)
    }

    init(item: BaseItemDto) {
        self.item = item
        super.init()
    }

    @Function(\Action.Cases.refresh)
    private func _refresh() async throws {
        guard !background.is(.updating) else { return }
        try await refreshRecordingTimers(using: requireRecordingTimers(item: item))
    }

    @Function(\Action.Cases.toggleRecording)
    private func _toggleRecording() async throws {
        let client = try requireRecordingTimers(item: item)
        let state = try await refreshRecordingTimers(using: client)
        guard try await client.toggleRecording(state) else { return }
        try client.checkBinding()
        Notifications[.recordingTimersDidChange].post()
        try await refreshRecordingTimers(using: client)
    }

    @Function(\Action.Cases.toggleSeriesRecording)
    private func _toggleSeriesRecording() async throws {
        let client = try requireRecordingTimers(item: item)
        let state = try await refreshRecordingTimers(using: client)
        guard try await client.toggleSeriesRecording(state) else { return }
        try client.checkBinding()
        Notifications[.recordingTimersDidChange].post()
        try await refreshRecordingTimers(using: client)
    }

    @Function(\Action.Cases.updateRecordingTimer)
    private func _updateRecordingTimer(_ updatedRecordingTimer: TimerInfoDto) async throws {
        guard updatedRecordingTimer.id != nil else { return }
        let client = try requireRecordingTimers(item: item)
        try await client.update(updatedRecordingTimer)
        try client.checkBinding()
        Notifications[.recordingTimersDidChange].post()
        events.send(.updated)
        try await refreshRecordingTimers(using: client)
    }

    @Function(\Action.Cases.updateSeriesRecordingTimer)
    private func _updateSeriesRecordingTimer(_ updatedSeriesRecordingTimer: SeriesTimerInfoDto) async throws {
        guard updatedSeriesRecordingTimer.id != nil else { return }
        let client = try requireRecordingTimers(item: item)
        try await client.update(updatedSeriesRecordingTimer)
        try client.checkBinding()
        Notifications[.recordingTimersDidChange].post()
        events.send(.updated)
        try await refreshRecordingTimers(using: client)
    }

    @discardableResult
    private func refreshRecordingTimers(using client: RecordingTimersClient) async throws -> RecordingTimerSnapshot {
        let state = try await client.snapshot()
        try client.checkBinding()
        program = state.program
        recordingTimer = state.recordingTimer
        seriesRecordingTimer = state.seriesRecordingTimer
        return state
    }
}
