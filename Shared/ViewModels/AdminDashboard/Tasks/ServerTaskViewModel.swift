//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation
import JellyfinAPI
import SwiftfinCollections
import SwiftfinServerOperations

@MainActor
@Stateful
final class ServerTaskViewModel: ViewModel, @MainActor Identifiable {

    @CasePathable
    enum Action {
        case start
        case stop
        case addTrigger(TaskTriggerInfo)
        case removeTrigger(TaskTriggerInfo)

        var transition: Transition {
            .background(.updating)
        }
    }

    enum BackgroundState {
        case updating
    }

    enum State {
        case error
        case initial
    }

    @Published
    var task: TaskInfo

    var id: String? {
        task.id
    }

    init(task: TaskInfo) {
        self.task = task
    }

    @Function(\Action.Cases.start)
    private func _start() async throws {
        guard let id = task.id else { return }

        task.state = .running

        try await requireServerOperations().startTask(id: id)
    }

    @Function(\Action.Cases.stop)
    private func _stop() async throws {
        guard let id = task.id else { return }

        task.state = .cancelling

        try await requireServerOperations().stopTask(id: id)
    }

    @Function(\Action.Cases.addTrigger)
    private func _addTrigger(_ trigger: TaskTriggerInfo) async throws {
        let updatedTriggers = (task.triggers ?? [])
            .appending(trigger)

        try await updateTriggers(updatedTriggers)
    }

    @Function(\Action.Cases.removeTrigger)
    private func _removeTrigger(_ trigger: TaskTriggerInfo) async throws {
        let updatedTriggers = ServerOperationsPolicy.triggers(removing: trigger, from: task.triggers ?? [])

        try await updateTriggers(updatedTriggers)
    }

    private func updateTriggers(_ updatedTriggers: [TaskTriggerInfo]) async throws {
        guard let id = task.id else { return }

        let previousTriggers = task.triggers
        task.triggers = updatedTriggers

        do {
            try await requireServerOperations().updateTriggers(id: id, triggers: updatedTriggers)
        } catch {
            task.triggers = previousTriggers
            throw error
        }
    }
}
