//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import CasePaths
import Combine
import FactoryKit
import Foundation
import Get
import JellyfinAPI
import Logging
import OrderedCollections
import StatefulMacros
import SwiftfinAccountAccess
import SwiftfinAccountModels
import SwiftfinAccountStore
import SwiftfinCollections
import SwiftfinLocalization
import SwiftfinStoredValues
import SwiftfinText
import SwiftUI

// TODO: instead of just signing in duplicate user, send event for alert
//       to override existing user access token?
//       - won't require deleting and re-signing in user for password changes
//       - account for local device auth required
// TODO: ignore NSURLErrorDomain Code=-999 cancelled error on sign in
//       - need to make NSError wrappers anyways

@MainActor
@Stateful
final class UserSignInViewModel: ObservableObject {

    typealias AccessPolicyPair = (policy: LocalUserAccessPolicy, evaluated: any EvaluatedLocalUserAccessPolicy)
    typealias UserStateDataPair = (state: (state: UserState, accessToken: String), data: UserDto)

    @MainActor
    struct EvaluatedPolicyMap {
        let action: @MainActor @Sendable (any EvaluatedLocalUserAccessPolicy) -> any EvaluatedLocalUserAccessPolicy

        func callAsFunction(evaluatedPolicy: any EvaluatedLocalUserAccessPolicy) -> any EvaluatedLocalUserAccessPolicy {
            action(evaluatedPolicy)
        }
    }

    @CasePathable
    enum Action {
        case cancel
        case error
        case getPublicData
        case signIn(username: String, password: String)
        case signInQuickConnect(secret: String, access: AccountAccessClient)

        case save(
            user: UserStateDataPair,
            authenticationAction: (action: LocalUserAuthenticationAction, accessPolicy: LocalUserAccessPolicy, reason: String?),
            evaluatedPolicyMap: EvaluatedPolicyMap
        )
        case saveExisting(
            user: UserStateDataPair,
            replaceForAccessToken: Bool,
            authenticationAction: (action: LocalUserAuthenticationAction, accessPolicy: LocalUserAccessPolicy, reason: String?),
            evaluatedPolicyMap: EvaluatedPolicyMap
        )

        var transition: Transition {
            switch self {
            case .cancel:
                .to(.initial)
            case .error, .save, .saveExisting:
                .none
            case .getPublicData:
                .background(.gettingPublicData)
            case .signIn, .signInQuickConnect:
                .loop(.signingIn)
            }
        }
    }

    enum BackgroundState {
        case gettingPublicData
    }

    enum Event {
        case connected(UserStateDataPair)
        case existingUser(UserStateDataPair)
        case saved(UserState)
    }

    enum State {
        case initial
        case signingIn
    }

    @Published
    private(set) var isQuickConnectEnabled = false
    @Published
    private(set) var publicUsers: [UserDto] = []
    @Published
    private(set) var serverDisclaimer: String? = nil

    private let logger = Logger.swiftfin()
    private var cancellables = Set<AnyCancellable>()

    let server: ServerState

    init(server: ServerState) {
        self.server = server
    }

    @Function(\Action.Cases.getPublicData)
    private func _getPublicData() async throws {
        let client = server.accountAccess
        let options = try await client.loginOptions()
        try client.checkBinding()
        self.isQuickConnectEnabled = options.quickConnectEnabled
        self.publicUsers = options.users
        self.serverDisclaimer = options.disclaimer
    }

    @Function(\Action.Cases.signIn)
    private func _signIn(
        _ username: String,
        _ password: String
    ) async throws {
        let username = username
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: .objectReplacement)

        let password = password
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: .objectReplacement)

        let response = try await server.accountAccess.signIn(username: username, password: password)

        let accessToken = response.accessToken
        let userData = response.user
        let id = response.userID
        let authenticatedUsername = response.username

        if let existingUser = existingUser(id: id) {
            events.send(.existingUser(((existingUser, accessToken), userData)))
        } else {
            let newUserState = UserState(
                id: id,
                serverID: server.id,
                username: authenticatedUsername
            )

            events.send(.connected(((newUserState, accessToken), userData)))
        }
    }

    @Function(\Action.Cases.signInQuickConnect)
    private func _signInQuickConnect(
        _ secret: String,
        _ access: AccountAccessClient
    ) async throws {
        let response = try await access.signIn(quickConnectSecret: secret)
        try access.checkBinding()

        let accessToken = response.accessToken
        let userData = response.user
        let id = response.userID
        let username = response.username

        if let existingUser = existingUser(id: id) {
            events.send(.existingUser(((existingUser, accessToken), userData)))
        } else {
            let newUserState = UserState(
                id: id,
                serverID: server.id,
                username: username
            )

            events.send(.connected(((newUserState, accessToken), userData)))
        }
    }

    private func existingUser(id: String) -> UserState? {
        StoredValues[.User.users]
            .first { $0.id == id }
    }

    @Function(\Action.Cases.save)
    private func _save(
        _ user: UserStateDataPair,
        _ authenticationAction: (action: LocalUserAuthenticationAction, accessPolicy: LocalUserAccessPolicy, reason: String?),
        _ evaluatedPolicyMap: EvaluatedPolicyMap
    ) async throws {

        let accessPolicy = authenticationAction.accessPolicy

        let evaluatedPolicy = try await evaluatedPolicyMap(
            evaluatedPolicy: authenticationAction.action(
                policy: accessPolicy,
                reason: authenticationAction.reason
            )
        )

        let userState = user.state.state

        let savedUserState = userState
        try Container.shared.localAccountStore().saveAuthenticatedUser(
            savedUserState,
            accessToken: user.state.accessToken,
            pin: (evaluatedPolicy as? PinEvaluatedUserAccessPolicy)?.pin
        )

        savedUserState.accessPolicy = accessPolicy
        savedUserState.data = user.data

        if let evaluatedPinPolicy = evaluatedPolicy as? PinEvaluatedUserAccessPolicy {
            if let pinHint = evaluatedPinPolicy.pinHint {
                savedUserState.pinHint = pinHint
            }
        }

        events.send(.saved(savedUserState))
    }

    @Function(\Action.Cases.saveExisting)
    private func _saveExisting(
        _ user: UserStateDataPair,
        _ replaceForAccessToken: Bool,
        _ authenticationAction: (action: LocalUserAuthenticationAction, accessPolicy: LocalUserAccessPolicy, reason: String?),
        _ evaluatedPolicyMap: EvaluatedPolicyMap
    ) async throws {

        let accessPolicy = authenticationAction.accessPolicy

        let evaluatedPolicy = try await evaluatedPolicyMap(
            evaluatedPolicy: authenticationAction.action(
                policy: accessPolicy,
                reason: authenticationAction.reason
            )
        )

        if let evaluatedPinPolicy = evaluatedPolicy as? PinEvaluatedUserAccessPolicy {
            guard user.state.state.pin == evaluatedPinPolicy.pin else {
                throw ErrorMessage(L10n.incorrectPinForUser(user.state.state.username))
            }
        }

        if replaceForAccessToken {
            try user.state.state.storeAccessToken(user.state.accessToken)
        }

        events.send(.saved(user.state.state))
    }
}
