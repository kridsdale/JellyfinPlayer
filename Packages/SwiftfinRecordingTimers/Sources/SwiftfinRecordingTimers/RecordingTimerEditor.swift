//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation
import JellyfinAPI

public enum RecordingTimerEdit: Sendable {
    case toggleRecording
    case toggleSeriesRecording
    case update(TimerInfoDto)
    case updateSeries(SeriesTimerInfoDto)
}

/// Owns one captured account/item's serial command and reload sequence.
/// Platform publication callbacks are checked before and after reentrant delivery.
@MainActor
public final class RecordingTimerEditor {
    public typealias Checkpoint = @MainActor @Sendable () throws -> Void
    public typealias Publish = @MainActor @Sendable (RecordingTimerSnapshot) throws -> Void
    private let client: RecordingTimersClient
    private var tail: Task<Void, Never>?
    private var generation: UUID?
    public init(client: RecordingTimersClient) {
        self.client = client
    }

    public func checkBinding() throws {
        try client.checkBinding()
    }

    private func check(_ validate: Checkpoint) throws {
        try client.checkBinding()
        try validate()
        try client.checkBinding()
    }

    private func snapshot(validate: Checkpoint, publish: Publish) async throws -> RecordingTimerSnapshot {
        try check(validate)
        let state = try await client.snapshot()
        try check(validate)
        try publish(state)
        try check(validate)
        return state
    }

    public func refresh(validate: @escaping Checkpoint = {}, publish: @escaping Publish = { _ in }) async throws {
        try check(validate)
        let pending = tail
        await pending?.value
        do { _ = try await snapshot(validate: validate, publish: publish) }
        catch { try check(validate)
            throw error
        }
    }

    public func edit(
        _ edit: RecordingTimerEdit,
        validate: @escaping Checkpoint = {},
        publish: @escaping Publish = { _ in },
        changed: @escaping @MainActor @Sendable () throws -> Void = {}
    ) async throws {
        try check(validate)
        let previous = tail, ticket = UUID()
        generation = ticket
        let job = Task {
            await previous?.value
            try self.check(validate)
            do {
                switch edit {
                case .toggleRecording, .toggleSeriesRecording:
                    let state = try await self.snapshot(validate: validate, publish: publish)
                    let changed = try await (edit.isSeriesToggle ? self.client.toggleSeriesRecording(state) : self.client
                        .toggleRecording(state))
                    guard changed else { return }
                case let .update(timer):
                    guard timer.id != nil else { return }
                    try await self.client.update(timer)
                case let .updateSeries(timer):
                    guard timer.id != nil else { return }
                    try await self.client.update(timer)
                }
                try self.check(validate)
                try changed()
                try self.check(validate)
                _ = try await self.snapshot(validate: validate, publish: publish)
            } catch { try self.check(validate)
                throw error
            }
        }
        tail = Task { _ = try? await job.value }
        defer {
            if generation == ticket {
                generation = nil
                tail = nil
            }
        }
        try await withTaskCancellationHandler {
            try await job.value
            try check(validate)
        } onCancel: { job.cancel() }
    }
}

private extension RecordingTimerEdit {
    var isSeriesToggle: Bool {
        if case .toggleSeriesRecording = self {
            true
        } else {
            false
        }
    }
}
