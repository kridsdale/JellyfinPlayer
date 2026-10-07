//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import CasePaths
import Combine
import Dispatch
import JellyfinAPI
import StatefulMacros
import SwiftfinServerOperations
import SwiftfinUserAdministration

@MainActor
@Stateful
final class ServerActivityDetailViewModel: ViewModel {

    @CasePathable
    enum Action {
        case refresh

        var transition: Transition {
            .loop(.refreshing)
                .whenBackground(.refreshing)
        }
    }

    enum BackgroundState {
        case refreshing
    }

    enum State {
        case initial
        case error
        case refreshing
    }

    @Published
    var log: ActivityLogEntry
    @Published
    var user: UserDto?
    @Published
    var item: BaseItemDto?

    init(log: ActivityLogEntry, user: UserDto?) {
        self.log = log
        self.user = user
        super.init()
    }

    @Function(\Action.Cases.refresh)
    private func _refresh() async {
        do {
            let operations = try requireServerOperations()
            let accounts = try requireUserAdministration()
            async let fetchedItem = readItem(log.itemID, operations: operations)
            async let fetchedUser = readUser(log.userID, accounts: accounts)
            let results = try await (fetchedItem, fetchedUser)
            item = results.0
            user = results.1
        } catch is CancellationError {
            return
        } catch {
            item = nil
            user = nil
        }
    }

    private func readItem(_ itemID: String?, operations: ServerOperationsClient) async throws -> BaseItemDto? {
        guard let itemID else { return nil }
        return try await operations.activityItem(id: itemID)
    }

    private func readUser(_ userID: String?, accounts: UserAdministrationClient) async throws -> UserDto? {
        guard let userID else { return nil }
        return try await accounts.user(id: userID)
    }
}
