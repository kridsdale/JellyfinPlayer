//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Combine
import Foundation
import JellyfinAPI
import OrderedCollections
import SwiftfinCollections
import SwiftfinServerOperations
import SwiftUI

@MainActor
@Stateful
final class DevicesViewModel: ViewModel {

    @CasePathable
    enum Action {
        case refresh
        case delete(ids: Set<String>)
        case update(id: String, options: DeviceOptionsDto)

        var transition: Transition {
            switch self {
            case .refresh:
                .loop(.refreshing)
                    .whenBackground(.refreshing)
            case .delete, .update:
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
        case refreshing
    }

    @Published
    private(set) var devices: [DeviceInfoDto] = []

    @Function(\Action.Cases.refresh)
    private func _refresh() async throws {
        guard let values = try await requireServerOperations().devices() else { return }
        devices = values
    }

    @Function(\Action.Cases.update)
    private func _update(_ id: String, _ options: DeviceOptionsDto) async throws {
        try await requireServerOperations().updateDevice(id: id, options: options)

        let deviceIndices = devices.indices.filter { devices[$0].id == id }

        for index in deviceIndices {
            devices[index].customName = options.customName
        }

        events.send(.updated)
    }

    @Function(\Action.Cases.delete)
    private func _delete(_ ids: Set<String>) async throws {
        guard ids.isNotEmpty else { return }
        let deleted = try await requireServerOperations().deleteDevices(ids: ids)
        devices = devices.subtracting(deleted, using: \.id)
    }
}
