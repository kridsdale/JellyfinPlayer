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
import SwiftfinTime
import SwiftfinUserAdministration

@MainActor
@Stateful
final class AddServerUserViewModel: ViewModel {

    @CasePathable
    enum Action {
        case cancel
        case add(username: String, password: String)

        var transition: Transition {
            switch self {
            case .cancel:
                .to(.initial)
            case .add:
                .to(.addingUser, then: .initial)
            }
        }
    }

    enum Event {
        case created(user: UserDto)
        case error
    }

    enum State: Hashable {
        case addingUser
        case initial
    }

    @Function(\Action.Cases.add)
    private func _add(_ username: String, _ password: String) async throws {
        let accounts = try requireUserAdministration()
        let user = try await accounts.create(name: username, password: password)

        try await Task.sleep(for: .seconds(5))
        try accounts.checkBinding()

        events.send(.created(user: user))
    }
}
