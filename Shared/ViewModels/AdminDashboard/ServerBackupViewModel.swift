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
final class ServerBackupViewModel: ViewModel {

    @CasePathable
    enum Action {
        case refresh
        case createBackup(options: BackupOptionsDto)
        case restore(backup: BackupManifestDto)

        var transition: Transition {
            switch self {
            case .refresh:
                .to(.refreshing, then: .initial)
            case .createBackup:
                .background(.creating)
            case .restore:
                .background(.restoring)
            }
        }
    }

    enum BackgroundState {
        case creating
        case restoring
    }

    enum Event {
        case created
        case restored
    }

    enum State {
        case initial
        case error
        case refreshing
    }

    @Published
    private(set) var backups: [BackupManifestDto] = []

    @Function(\Action.Cases.refresh)
    private func _refresh() async throws {
        backups = try await requireServerOperations().backups()
    }

    @Function(\Action.Cases.createBackup)
    private func _createBackup(_ options: BackupOptionsDto) async throws {
        let backup = try await requireServerOperations().createBackup(options: options)
        backups = backups.prepending(backup)
        events.send(.created)
    }

    @Function(\Action.Cases.restore)
    private func _restore(_ backup: BackupManifestDto) async throws {
        try await requireServerOperations().restoreBackup(path: backup.path)
        events.send(.restored)
    }
}
