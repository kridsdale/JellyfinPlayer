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
import JellyfinAPI
import StatefulMacros
import SwiftfinAccountAccess
import SwiftfinAccountModels
import SwiftfinAccountStore
import SwiftfinAsyncStreams
import SwiftfinLocalization
import SwiftfinUIState

@MainActor
@Stateful
final class UserSignInViewModel: ObservableObject {
    typealias AccessPolicyPair = (policy: LocalUserAccessPolicy, evaluated: any EvaluatedLocalUserAccessPolicy)
    typealias UserStateDataPair = (state: (state: UserState, accessToken: String), data: UserDto)
    typealias AuthenticationAction = (action: LocalUserAuthenticationAction, accessPolicy: LocalUserAccessPolicy, reason: String?)
    @MainActor
    struct EvaluatedPolicyMap {
        let action: @MainActor @Sendable (any EvaluatedLocalUserAccessPolicy) -> any EvaluatedLocalUserAccessPolicy
        func callAsFunction(evaluatedPolicy: any EvaluatedLocalUserAccessPolicy)
        -> any EvaluatedLocalUserAccessPolicy {
            action(evaluatedPolicy)
        }
    }

    struct Request: Sendable {
        let access: AccountAccessClient
        let selection: UserSessionManager.SelectionRequest?
        let validate: AsyncOperationGate.Checkpoint
    }

    struct SaveRequest: Sendable {
        let snapshot: UserAdmissionSnapshot
        let selection: UserSessionManager.SelectionRequest
        let validate: AsyncOperationGate.Checkpoint
    }

    private struct PendingAuthentication {
        let user: UserStateDataPair
        let selection: UserSessionManager.SelectionRequest
        let validate: AsyncOperationGate.Checkpoint
    }

    @CasePathable
    enum Action {
        case cancel
        case error
        case runPublic(Request)
        case runSignIn(Request, String, String)
        case runQuick(Request, String, AccountAccessClient)
        case runSave(SaveRequest, UserStateDataPair, AuthenticationAction, EvaluatedPolicyMap)
        var transition: Transition {
            switch self {
            case .cancel: .to(.initial)
            case .error, .runSave: .none
            case .runPublic: .background(.gettingPublicData)
            case .runSignIn, .runQuick: .loop(.signingIn)
            }
        }
    }

    enum BackgroundState { case gettingPublicData }
    enum Event {
        case connected(UserStateDataPair)
        case existingUser(UserStateDataPair)
        case saved(UserState, UserSessionManager.SelectionRequest)
    }

    enum State { case initial, signingIn }
    @CommittedPublished
    private(set) var isQuickConnectEnabled = false {
        didSet { objectWillChange.send() }
    }

    @CommittedPublished
    private(set) var publicUsers: [UserDto] = [] {
        didSet { objectWillChange.send() }
    }

    @CommittedPublished
    private(set) var serverDisclaimer: String? = nil {
        didSet { objectWillChange.send() }
    }

    let server: ServerState
    private let store: LocalAccountStore
    private let originURL: URL
    private let originSessionID: ObjectIdentifier?
    private let reads = AsyncOperationGate()
    private let logins = AsyncOperationGate()
    private let saves = AsyncOperationGate()
    private var pending: PendingAuthentication?
    private var selectionIntent: UserSessionManager.SelectionRequest?
    private let sessions = Container.shared.userSessionManager()

    init(server: ServerState) {
        self.server = server
        store = Container.shared.localAccountStore()
        originURL = server.effectiveServerURL
        originSessionID = Container.shared.userSessionManager().currentSession.map(ObjectIdentifier.init)
    }

    private func checkOrigin() throws {
        try Task.checkCancellation()
        guard let current = store.servers.first(where: { $0.id == server.id }),
              store.effectiveURL(for: current) == originURL,
              Container.shared.userSessionManager().currentSession.map(ObjectIdentifier.init) == originSessionID
        else { throw CancellationError() }
    }

    private func request(_ gate: AsyncOperationGate, selectingAccount: Bool = false) -> Request? {
        guard (try? checkOrigin()) != nil else { return nil }
        let access = server.accountAccess
        guard (try? access.checkBinding()) != nil else { return nil }
        let selection: UserSessionManager.SelectionRequest?
        if selectingAccount {
            guard let next = try? sessions.beginSignInIntent() else { return nil }
            selection = next
            selectionIntent = next
        } else {
            selection = nil
        }
        let receipt = gate.begin()
        return Request(access: access, selection: selection, validate: { [weak self] in
            try receipt()
            try selection?.check()
            guard let self else { throw CancellationError() }
            try checkOrigin()
            try access.checkBinding()
            try receipt()
        })
    }

    func getPublicData() {
        if let request = request(reads) {
            runPublic(request)
        }
    }

    func signIn(username: String, password: String) {
        guard let request = request(logins, selectingAccount: true) else { return }
        saves.cancel()
        pending = nil
        runSignIn(request, username, password)
    }

    func signInQuickConnect(secret: String, access: AccountAccessClient) {
        guard let request = request(logins, selectingAccount: true) else { return }
        saves.cancel()
        pending = nil
        runQuick(request, secret, access)
    }

    func signInQuickConnect(secret: String, access: AccountAccessClient) async {
        guard let request = request(logins, selectingAccount: true) else { return }
        saves.cancel()
        pending = nil
        await runQuick(request, secret, access)
    }

    func save(user: UserStateDataPair, authenticationAction: AuthenticationAction, evaluatedPolicyMap: EvaluatedPolicyMap) {
        admit(user, mode: .new, action: authenticationAction, map: evaluatedPolicyMap)
    }

    func saveExisting(
        user: UserStateDataPair,
        replaceForAccessToken: Bool,
        authenticationAction: AuthenticationAction,
        evaluatedPolicyMap: EvaluatedPolicyMap
    ) {
        admit(user, mode: .existing(replaceAccessToken: replaceForAccessToken), action: authenticationAction, map: evaluatedPolicyMap)
    }

    private func admit(_ user: UserStateDataPair, mode: UserAdmissionMode, action: AuthenticationAction, map: EvaluatedPolicyMap) {
        guard let pending, pending.user.state.state == user.state.state,
              pending.user.state.accessToken == user.state.accessToken, pending.user.data == user.data,
              (try? pending.validate()) != nil else { return }
        do {
            let snapshot = try store.prepareUserAdmission(user: user.state.state, mode: mode, endpoint: originURL)
            let receipt = saves.begin()
            let check: AsyncOperationGate.Checkpoint = { [weak self] in
                try receipt()
                try pending.validate()
                guard let self else { throw CancellationError() }
                try checkOrigin()
                try receipt()
            }
            runSave(.init(snapshot: snapshot, selection: pending.selection, validate: check), user, action, map)
        } catch { /* Invalid/stale local admission never reaches native authentication. */ }
    }

    @Function(\Action.Cases.cancel)
    private func _cancel() async {
        reads.cancel()
        logins.cancel()
        saves.cancel()
        pending = nil
        if let selectionIntent {
            sessions.cancelPendingSignIn(selectionIntent)
        }
        selectionIntent = nil
    }

    @Function(\Action.Cases.runPublic)
    private func _runPublic(_ request: Request) async throws {
        do {
            try request.validate()
            let options = try await request.access.loginOptions()
            try request.validate()
            isQuickConnectEnabled = options.quickConnectEnabled
            try request.validate()
            publicUsers = options.users
            try request.validate()
            serverDisclaimer = options.disclaimer
        } catch { try request.validate()
            throw error
        }
    }

    private func received(_ response: AccountAuthentication, request: Request) throws {
        try request.validate()
        guard !response.userID.isEmpty, !response.accessToken.isEmpty,
              response.user.serverID == nil || response.user.serverID == server.id
        else { throw AccountStoreError.identityMismatch }
        let matches = store.users.filter { $0.id == response.userID }
        guard matches.allSatisfy({ $0.serverID == server.id }) else { throw AccountStoreError.identityMismatch }
        let existing = matches.first
        let user = existing ?? UserState(id: response.userID, serverID: server.id, username: response.username)
        let pair: UserStateDataPair = ((user, response.accessToken), response.user)
        guard let selection = request.selection else { throw CancellationError() }
        pending = .init(user: pair, selection: selection, validate: request.validate)
        try request.validate()
        if existing != nil {
            events.send(.existingUser(pair))
        } else {
            events.send(.connected(pair))
        }
    }

    @Function(\Action.Cases.runSignIn)
    private func _runSignIn(_ request: Request, _ username: String, _ password: String) async throws {
        do {
            try request.validate()
            let username = username.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: .objectReplacement)
            let password = password.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: .objectReplacement)
            try await received(request.access.signIn(username: username, password: password), request: request)
        } catch { try request.validate()
            if let selection = request.selection {
                sessions.cancelPendingSignIn(selection)
            }
            throw error
        }
    }

    @Function(\Action.Cases.runQuick)
    private func _runQuick(_ request: Request, _ secret: String, _ access: AccountAccessClient) async throws {
        do {
            try request.validate()
            try access.checkBinding()
            let response = try await access.signIn(quickConnectSecret: secret)
            try access.checkBinding()
            try received(response, request: request)
        } catch { try request.validate()
            if let selection = request.selection {
                sessions.cancelPendingSignIn(selection)
            }
            throw error
        }
    }

    @Function(\Action.Cases.runSave)
    private func _runSave(
        _ request: SaveRequest,
        _ user: UserStateDataPair,
        _ action: AuthenticationAction,
        _ map: EvaluatedPolicyMap
    ) async throws {
        do {
            try request.validate()
            let evaluated = try await map(evaluatedPolicy: action.action(policy: action.accessPolicy, reason: action.reason))
            try request.validate()
            let pin = evaluated as? PinEvaluatedUserAccessPolicy
            let saved = try store.commitUserAdmission(
                request.snapshot,
                data: user.data,
                accessToken: user.state.accessToken,
                policy: action.accessPolicy,
                pin: pin?.pin,
                pinHint: pin?.pinHint,
                validate: request.validate
            )
            try request.validate()
            events.send(.saved(saved, request.selection))
        } catch AccountStoreError.incorrectPIN {
            try request.validate()
            throw ErrorMessage(L10n.incorrectPinForUser(user.state.state.username))
        } catch { try request.validate()
            throw error
        }
    }
}
