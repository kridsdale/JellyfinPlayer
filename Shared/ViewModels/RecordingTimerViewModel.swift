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
import SwiftfinAsyncStreams
import SwiftfinRecordingTimers
import SwiftfinUIState

@MainActor
@Stateful
final class RecordingTimerViewModel: ViewModel {
    struct Request: Sendable { let validate: AsyncOperationGate.Checkpoint }
    @CasePathable
    enum Action {
        case runRefresh(Request)
        case runEdit(Request, RecordingTimerEdit, Bool)
        var transition: Transition {
            switch self {
            case .runRefresh: .background(.refreshing)
            case .runEdit: .background(.updating)
            }
        }
    }

    enum BackgroundState {
        case refreshing
        case updating
    }

    enum Event { case updated }
    enum State {
        case error
        case initial
    }

    @CommittedPublished
    private var snapshot: RecordingTimerSnapshot? {
        didSet { objectWillChange.send() }
    }

    var program: BaseItemDto? {
        snapshot?.program
    }

    var recordingTimer: TimerInfoDto? {
        snapshot?.recordingTimer
    }

    var seriesRecordingTimer: SeriesTimerInfoDto? {
        snapshot?.seriesRecordingTimer
    }

    private var editor: RecordingTimerEditor?
    private let reads = AsyncOperationGate()
    private let edits = AsyncOperationGate()
    var canManageRecordings: Bool {
        (program?.canBeRecorded == true || recordingTimer != nil || seriesRecordingTimer != nil)
            && !background.is(.refreshing) && !background.is(.updating)
    }

    init(item: BaseItemDto) {
        super.init()
        editor = try? RecordingTimerEditor(client: requireRecordingTimers(item: item))
    }

    private func request(_ gate: AsyncOperationGate) -> Request? {
        guard let editor, (try? editor.checkBinding()) != nil else { return nil }
        let receipt = gate.begin()
        return .init(validate: { [weak self] in
            try receipt()
            try editor.checkBinding()
            guard self != nil else { throw CancellationError() }
            try receipt()
        })
    }

    func refresh() {
        guard !background.is(.updating), let request = request(reads) else { return }
        runRefresh(request)
    }

    func refresh() async {
        guard !background.is(.updating), let request = request(reads) else { return }
        await runRefresh(request)
    }

    func toggleRecording() {
        submit(.toggleRecording, updatedEvent: false)
    }

    func toggleSeriesRecording() {
        submit(.toggleSeriesRecording, updatedEvent: false)
    }

    func updateRecordingTimer(_ timer: TimerInfoDto) {
        guard timer.id != nil else { return }
        submit(.update(timer), updatedEvent: true)
    }

    func updateSeriesRecordingTimer(_ timer: SeriesTimerInfoDto) {
        guard timer.id != nil else { return }
        submit(.updateSeries(timer), updatedEvent: true)
    }

    private func submit(_ edit: RecordingTimerEdit, updatedEvent: Bool) {
        guard let request = request(edits) else { return }
        reads.cancel()
        runEdit(request, edit, updatedEvent)
    }

    private func publish(_ value: RecordingTimerSnapshot, request: Request) throws {
        try request.validate()
        snapshot = value
        try request.validate()
    }

    @Function(\Action.Cases.runRefresh)
    private func _runRefresh(_ request: Request) async throws {
        guard !background.is(.updating), let editor else { return }
        do { try await editor.refresh(validate: request.validate, publish: { [weak self] value in
            guard let self else { throw CancellationError() }
            try publish(value, request: request)
        }) } catch { try request.validate()
            throw error
        }
    }

    @Function(\Action.Cases.runEdit)
    private func _runEdit(_ request: Request, _ edit: RecordingTimerEdit, _ updatedEvent: Bool) async throws {
        guard let editor else { return }
        do { try await editor.edit(edit, validate: request.validate, publish: { [weak self] value in
            guard let self else { throw CancellationError() }
            try publish(value, request: request)
        }, changed: { [weak self] in
            try request.validate()
            guard let self else { throw CancellationError() }
            Notifications[.recordingTimersDidChange].post()
            try request.validate()
            if updatedEvent {
                events.send(.updated)
                try request.validate()
            }
        }) } catch { try request.validate()
            throw error
        }
    }
}
