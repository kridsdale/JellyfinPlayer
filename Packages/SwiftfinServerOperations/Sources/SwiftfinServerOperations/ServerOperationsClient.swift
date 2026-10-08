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

/// Server process/tasks, diagnostics, device access and existing session controls.
@MainActor
public final class ServerOperationsClient {
    private let executor: AuthenticatedRequestExecutor
    private let deviceID: String
    public init(executor: AuthenticatedRequestExecutor, deviceID: String) {
        self.executor = executor
        self.deviceID = deviceID
    }

    public func checkBinding() throws {
        try executor.checkBinding()
    }

    public func activity(offset: Int, limit: Int, hasUserID: Bool?, minimumDate: Date?) async throws -> [ActivityLogEntry] {
        var p = Paths.GetLogEntriesParameters()
        p.startIndex = max(0, offset)
        p.limit = max(1, limit)
        p.hasUserID = hasUserID
        p.minDate = minimumDate
        return try await executor.value(for: Paths.getLogEntries(parameters: p)).items ?? []
    }

    public func logs() async throws -> [LogFile] {
        try await executor.value(for: Paths.getServerLogs)
    }

    public func activityItem(id: String) async throws -> BaseItemDto {
        try await executor.value(for: Paths.getItem(itemID: id))
    }

    public func keys() async throws -> [AuthenticationInfo]? {
        guard let items = try await executor.value(for: Paths.getKeys).items else { return nil }
        return ServerOperationsPolicy.sortedKeys(items)
    }

    public func createKey(name: String) async throws {
        try await executor.complete(Paths.createKey(app: name))
    }

    /// A creation and its refreshed list use the same captured account binding.
    public func createKeyAndReload(name: String) async throws -> [AuthenticationInfo]? {
        try await createKey(name: name)
        return try await keys()
    }

    public func revokeKey(token: String) async throws {
        try await executor.complete(Paths.revokeKey(key: token))
    }

    /// Revocation is acknowledged before the UI removes its old row. Later
    /// failures retain that acknowledgement, and every step uses one binding.
    public func replaceKey(
        name: String,
        token: String,
        didRevoke: @MainActor () -> Void
    ) async throws -> [AuthenticationInfo]? {
        try await revokeKey(token: token)
        didRevoke()
        return try await createKeyAndReload(name: name)
    }

    public func devices() async throws -> [DeviceInfoDto]? {
        guard let items = try await executor.value(for: Paths.getDevices()).items else { return nil }
        return ServerOperationsPolicy.sortedDevices(items)
    }

    public func updateDevice(id: String, options: DeviceOptionsDto) async throws {
        try await executor.complete(Paths.updateDeviceOptions(
            id: id,
            options
        ))
    }

    /// Protect the device that owns the captured transport, including during a batch.
    @discardableResult
    public func deleteDevices(ids: Set<String>) async throws -> Set<String> {
        try executor.checkBinding()
        let eligible = ids.filter { $0 != deviceID }
        guard !eligible.isEmpty else { return [] }
        try await executor.complete(Paths.deleteDevice(id: Array(eligible).sorted()))
        return eligible
    }

    public func tasks() async throws -> [TaskInfo] {
        try await executor.value(for: Paths.getTasks(isHidden: false, isEnabled: true))
    }

    public func startTask(id: String) async throws {
        try await executor.complete(Paths.startTask(taskID: id))
    }

    public func stopTask(id: String) async throws {
        try await executor.complete(Paths.stopTask(taskID: id))
    }

    public func updateTriggers(id: String, triggers: [TaskTriggerInfo]) async throws {
        try await executor.complete(Paths.updateTask(
            taskID: id,
            triggers
        ))
    }

    public func restart() async throws {
        try await executor.complete(Paths.restartApplication)
    }

    public func shutdown() async throws {
        try await executor.complete(Paths.shutdownApplication)
    }

    public func backups() async throws -> [BackupManifestDto] {
        try await executor.value(for: Paths.listBackups).sorted { $0.dateCreated > $1.dateCreated }
    }

    public func createBackup(options: BackupOptionsDto) async throws -> BackupManifestDto {
        try await executor
            .value(for: Paths.createBackup(options))
    }

    public func restoreBackup(path: String) async throws {
        let name = URL(fileURLWithPath: path).lastPathComponent
        try await executor.complete(Paths.startRestoreBackup(BackupRestoreRequestDto(archiveFileName: name)))
    }

    public func sessions(activeWithinSeconds: Int?) async throws -> [SessionInfoDto] {
        try await executor.value(for: Paths.getSessions(parameters: .init(activeWithinSeconds: activeWithinSeconds)))
    }

    public func play(
        sessionID: String,
        command: PlayCommand,
        itemIDs: [String],
        position: Int?,
        mediaSourceID: String?,
        audioIndex: Int?,
        subtitleIndex: Int?,
        startIndex: Int?
    ) async throws {
        try await executor.complete(Paths.play(
            sessionID: sessionID,
            parameters: .init(
                playCommand: command,
                itemIDs: itemIDs,
                startPositionTicks: position,
                mediaSourceID: mediaSourceID,
                audioStreamIndex: audioIndex,
                subtitleStreamIndex: subtitleIndex,
                startIndex: startIndex
            )
        ))
    }

    public func message(sessionID: String, command: MessageCommand) async throws {
        try await executor.complete(Paths.sendMessageCommand(
            sessionID: sessionID,
            command
        ))
    }

    public func playstate(sessionID: String, command: PlaystateCommand, position: Int?) async throws {
        try await executor.complete(Paths.sendPlaystateCommand(
            sessionID: sessionID,
            command: command.rawValue,
            seekPositionTicks: position
        ))
    }

    public func general(sessionID: String, command: GeneralCommandType) async throws {
        try await executor.complete(Paths.sendGeneralCommand(
            sessionID: sessionID,
            command: command.rawValue
        ))
    }
}
