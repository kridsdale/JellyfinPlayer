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
import SwiftfinAccountAccess
import SwiftfinAsyncStreams
import SwiftfinImages
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

    private let originalItemID: String?
    private let originalUserID: String?
    private var operations: ServerOperationsClient?
    private var accounts: UserAdministrationClient?
    private var access: AccountAccessClient?
    private let refreshGate = AsyncOperationGate()

    var profileImageSource: ImageSource {
        ImageSource(url: user?.id.flatMap { try? access?.profileURL(userID: $0, imageTag: user?.primaryImageTag) })
    }

    init(log: ActivityLogEntry, user: UserDto?) {
        self.originalItemID = log.itemID
        self.originalUserID = log.userID
        self.log = log
        self.user = user
        super.init()
        self.operations = try? requireServerOperations()
        self.accounts = try? requireUserAdministration()
        self.access = userSession?.accountAccess
    }

    @Function(\Action.Cases.refresh)
    private func _refresh() async {
        guard !Task.isCancelled else { return }
        let caller = refreshGate.begin()
        guard let operations, let accounts, let access else { return }
        let checkpoint: AsyncOperationGate.Checkpoint = {
            try caller()
            try operations.checkBinding()
            try accounts.checkBinding()
            try access.checkBinding()
            try caller()
        }
        do {
            try checkpoint()
            async let fetchedItem = readItem(originalItemID, operations: operations)
            async let fetchedUser = readUser(originalUserID, accounts: accounts)
            let results = try await (fetchedItem, fetchedUser)
            try checkpoint()
            item = results.0
            try checkpoint()
            user = results.1
        } catch is CancellationError { return
        } catch {
            guard (try? checkpoint()) != nil else { return }
            item = nil
            guard (try? checkpoint()) != nil else { return }
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
