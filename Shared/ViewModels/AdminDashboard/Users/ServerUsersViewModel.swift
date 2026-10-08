//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import CasePaths
import Combine
import Foundation
import IdentifiedCollections
import JellyfinAPI
import StatefulMacros
import SwiftfinAccountAccess
import SwiftfinAsyncStreams
import SwiftfinCollections
import SwiftfinImages
import SwiftfinUserAdministration
import SwiftUI

@MainActor
@Stateful
final class ServerUsersViewModel: ViewModel, Identifiable {

    @CasePathable
    enum Action {
        case refreshUser(String)
        case getUsers(isHidden: Bool, isDisabled: Bool)
        case deleteUsers([String])
        case appendUser(UserDto)

        var transition: Transition {
            switch self {
            case .refreshUser, .getUsers:
                .to(.content)
                    .whenBackground(.gettingUsers)
                    .onRepeat(.cancel)
            case .deleteUsers:
                .to(.content)
                    .whenBackground(.deletingUsers)
                    .onRepeat(.cancel)
            case .appendUser:
                .to(.content)
                    .whenBackground(.appendingUsers)
                    .onRepeat(.cancel)
            }
        }
    }

    enum BackgroundState {
        case gettingUsers
        case deletingUsers
        case appendingUsers
    }

    enum Event {
        case deleted
    }

    enum State {
        case content
        case error
        case initial
    }

    @Published
    var users: IdentifiedArrayOf<UserDto> = []

    private var accounts: UserAdministrationClient?
    private var access: AccountAccessClient?

    func profileImageSource(for user: UserDto) -> ImageSource {
        ImageSource(url: user.id.flatMap { try? access?.profileURL(userID: $0, imageTag: user.primaryImageTag) })
    }

    private func requireAccounts() throws -> UserAdministrationClient {
        guard let accounts else { throw UserSessionError.missingCurrentSession }
        try accounts.checkBinding()
        return accounts
    }

    // MARK: - Initializer

    override init() {
        super.init()
        accounts = try? requireUserAdministration()
        access = userSession?.accountAccess

        Notifications[.didChangeUserProfile]
            .publisher
            .sink { [weak self] userID in
                self?.refreshUser(userID)
            }
            .store(in: &cancellables)
    }

    // MARK: - Refresh User

    @Function(\Action.Cases.refreshUser)
    private func _refreshUser(_ userID: String) async throws {
        await cancel()

        let accounts = try requireAccounts()
        let newUser = try await accounts.user(id: userID)
        try accounts.checkBinding()

        if let index = users.firstIndex(where: { $0.id == userID }) {
            users[index] = newUser
        }
    }

    // MARK: - Load Users

    @Function(\Action.Cases.getUsers)
    private func _getUsers(_ isHidden: Bool, _ isDisabled: Bool) async throws {
        await cancel()
        let accounts = try requireAccounts()
        let users = try await accounts.users(
            isHidden: UserAdministrationClient.filterValue(isHidden),
            isDisabled: UserAdministrationClient.filterValue(isDisabled)
        )
        try accounts.checkBinding()
        self.users = IdentifiedArray(uniqueElements: UserAdministrationClient.sortedUsers(users))
    }

    // MARK: - Delete Users

    @Function(\Action.Cases.deleteUsers)
    private func _deleteUsers(_ ids: [String]) async throws {
        await cancel()
        let accounts = try requireAccounts()
        let deleted = try await accounts.deleteUsers(ids: ids)
        try accounts.checkBinding()
        users.removeAll { deleted.contains($0.id ?? "") }
        try accounts.checkBinding()
        events.send(.deleted)
    }

    // MARK: - Append User

    @Function(\Action.Cases.appendUser)
    private func _appendUser(_ user: UserDto) async {
        await cancel()

        guard let accounts, (try? accounts.checkBinding()) != nil else { return }
        users.append(user)
        guard (try? accounts.checkBinding()) != nil else { return }
        users.sort(by: { $0.name ?? "" < $1.name ?? "" })
        guard (try? accounts.checkBinding()) != nil else { return }
        events.send(.deleted)
    }
}
