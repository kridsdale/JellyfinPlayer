//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Combine
import Foundation
import IdentifiedCollections
import JellyfinAPI
import SwiftfinCollections
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

    // MARK: - Initializer

    override init() {
        super.init()

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

        let newUser = try await requireUserAdministration().user(id: userID)

        if let index = users.firstIndex(where: { $0.id == userID }) {
            users[index] = newUser
        }
    }

    // MARK: - Load Users

    @Function(\Action.Cases.getUsers)
    private func _getUsers(_ isHidden: Bool, _ isDisabled: Bool) async throws {
        await cancel()
        let users = try await requireUserAdministration().users(
            isHidden: UserAdministrationClient.filterValue(isHidden),
            isDisabled: UserAdministrationClient.filterValue(isDisabled)
        )
        self.users = IdentifiedArray(uniqueElements: UserAdministrationClient.sortedUsers(users))
    }

    // MARK: - Delete Users

    @Function(\Action.Cases.deleteUsers)
    private func _deleteUsers(_ ids: [String]) async throws {
        await cancel()
        let deleted = try await requireUserAdministration().deleteUsers(ids: ids)
        users.removeAll { deleted.contains($0.id ?? "") }
        events.send(.deleted)
    }

    // MARK: - Append User

    @Function(\Action.Cases.appendUser)
    private func _appendUser(_ user: UserDto) async {
        await cancel()

        users.append(user)
        users.sort(by: { $0.name ?? "" < $1.name ?? "" })
        events.send(.deleted)
    }
}
