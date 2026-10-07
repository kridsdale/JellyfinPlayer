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
import OrderedCollections
import StatefulMacros
import SwiftfinCollections
import SwiftfinLocalization
import SwiftfinServerOperations

@MainActor
@Stateful
final class APIKeysViewModel: ViewModel {

    @CasePathable
    enum Action {
        case refresh
        case create(name: String)
        case replace(key: AuthenticationInfo)
        case delete(key: AuthenticationInfo)

        var transition: Transition {
            switch self {
            case .refresh:
                .to(.refreshing, then: .initial)
            case .create, .replace, .delete:
                .background(.updating)
            }
        }
    }

    enum BackgroundState {
        case updating
    }

    enum Event {
        case createdKey
    }

    enum State {
        case initial
        case error
        case refreshing
    }

    @Published
    private(set) var apiKeys: [AuthenticationInfo] = []

    @Function(\Action.Cases.refresh)
    private func _refresh() async throws {
        guard let items = try await requireServerOperations().keys() else { return }
        apiKeys = items
    }

    @Function(\Action.Cases.create)
    private func _create(_ name: String) async throws {
        let operations = try requireServerOperations()
        if let keys = try await operations.createKeyAndReload(name: name) {
            apiKeys = keys
        }
        events.send(.createdKey)
    }

    @Function(\Action.Cases.replace)
    private func _replace(_ key: AuthenticationInfo) async throws {
        guard let name = key.appName, let token = key.accessToken else { throw ErrorMessage(L10n.unknownError) }
        let operations = try requireServerOperations()
        if let keys = try await operations.replaceKey(name: name, token: token, didRevoke: { [weak self] in
            self?.apiKeys.removeFirst(equalTo: key)
        }) {
            apiKeys = keys
        }
        events.send(.createdKey)
    }

    @Function(\Action.Cases.delete)
    private func _delete(_ key: AuthenticationInfo) async throws {
        guard let token = key.accessToken else { throw ErrorMessage(L10n.unknownError) }
        try await requireServerOperations().revokeKey(token: token)
        apiKeys.removeFirst(equalTo: key)
    }
}
