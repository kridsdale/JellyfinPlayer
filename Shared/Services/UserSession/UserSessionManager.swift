//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Combine
import Defaults
import FactoryKit
import Foundation
import JellyfinAPI
import Logging
import SwiftfinAccountAccess
import SwiftfinAccountModels
import SwiftfinAccountStore
import SwiftfinAsyncStreams
import SwiftfinLocalization
import SwiftfinPlaybackPreparation
import SwiftfinSessions
import SwiftfinStoredValues
import SwiftfinTime
import SwiftfinUIState

extension Container {

    @MainActor
    var userSessionManager: Factory<UserSessionManager> {
        self { UserSessionManager() }
            .singleton
    }

    @MainActor
    var currentUserSession: Factory<UserSession?> {
        self { self.userSessionManager().currentSession }
            .cached
    }
}

@MainActor
final class UserSessionManager: ObservableObject {

    enum State: Equatable {
        case initial
        case signedOut
        case signedIn
    }

    enum SignOutReason {
        case backgroundTimeout
        case explicit
    }

    enum AuthenticationError: Error {
        case missingAuthenticationAction
    }

    @Published
    private(set) var state: State = .initial

    @Published
    private(set) var currentSession: UserSession?

    @Published
    private(set) var pendingDeepLink: DeepLink?

    let routePublisher = PassthroughSubject<NavigationRoute, Never>()

    // App-owned routing results; transport/lifetime implementation stays in owners.
    enum SocketTrailerTarget: Sendable {
        case localItem(String)
        case external(String)
    }

    let socketCommands = ScopedPublisher<[ObjectIdentifier], RemotePlaybackIntent>()
    let socketItemRequest = LatestRequest<BaseItemDto>()
    let socketTrailerRequest = LatestRequest<SocketTrailerTarget>()

    var cancellables = Set<AnyCancellable>()

    let logger = Logger.swiftfin()

    private struct MetadataRefreshID: Hashable, Sendable {
        let serverID: String
        let userID: String
        let url: URL
    }

    private let metadataRefresh = SessionMetadataRefresh<MetadataRefreshID>()
    private let playerSelection = UIObjectSelection<MediaPlayerManager>()
    var mediaPlayerManager: MediaPlayerManager? {
        playerSelection.current
    }

    @MainActor
    var hasActivePlayback: Bool {
        guard let mediaPlayerManager else { return false }
        return mediaPlayerManager.state != .stopped
    }

    init() {
        setupObservations()
    }

    typealias SelectionRequest = SessionSelectionCoordinator<UserSession>.Request

    struct SignInRequest {
        let selection: SelectionRequest
        let session: UserSession
        let policy: LocalUserAccessPolicy
    }

    func start() async {
        guard state == .initial else { return }
        do {
            guard let request = try selections.begin(priority: .restoration) else { return }
            await restore(request, signOut: Defaults[.signOutOnClose], refreshMetadata: false)
        } catch is CancellationError {
            return
        } catch {
            logger.error("Unable to restore launch session", metadata: ["error": .string(error.localizedDescription)])
        }
    }

    /// Capture an exact account choice before native authentication or scheduling.
    func beginSignIn(
        userID: String,
        serverID: String,
        selection: SelectionRequest? = nil,
        validate: @escaping AsyncOperationGate.Checkpoint = {},
        validateSession: @escaping @MainActor @Sendable (UserSession) throws -> Void = { _ in }
    ) throws -> SignInRequest {
        try Task.checkCancellation()
        try validate()
        guard let user = StoredValues[.User.users].first(where: { $0.id == userID && $0.serverID == serverID }),
              let server = StoredValues[.Server.servers].first(where: { $0.id == serverID })
        else { throw UserSessionError.invalidStoredSession(userID: userID) }
        let session = UserSession(server: server, user: user)
        let policy = user.accessPolicy
        let accountCheck: AsyncOperationGate.Checkpoint = {
            try validate()
            guard StoredValues[.User.users].contains(where: { $0.id == userID && $0.serverID == serverID }),
                  StoredValues[.Server.servers].contains(where: { $0.id == serverID }),
                  user.accessPolicy == policy
            else { throw CancellationError() }
            try validateSession(session)
        }
        let receipt: SelectionRequest
        if let selection {
            receipt = selection.validating(accountCheck)
            try receipt.check()
        } else {
            guard let next = try selections.begin(priority: .explicit, validate: accountCheck) else { throw CancellationError() }
            receipt = next
        }
        return .init(selection: receipt, session: session, policy: policy)
    }

    func beginSignInIntent() throws -> SelectionRequest {
        guard let request = try selections.begin(priority: .explicit) else { throw CancellationError() }
        return request
    }

    func cancelPendingSignIn(_ request: SelectionRequest) {
        selections.cancelPending(request)
    }

    func signIn(_ request: SignInRequest, authenticationAction: LocalUserAuthenticationAction? = nil) async throws {
        try await activateSignIn(request, prepare: { checkpoint in
            if let authenticationAction {
                try await self.authenticate(
                    user: request.session.user,
                    policy: request.policy,
                    authenticationAction: authenticationAction,
                    validate: checkpoint
                )
            }
        })
    }

    /// Child admission participates in the same sequence as ordinary UI choices.
    func signIn(
        userID: String,
        serverID: String,
        validate: @escaping AsyncOperationGate.Checkpoint,
        validateSession: @escaping @MainActor @Sendable (UserSession) throws -> Void
    ) async throws {
        let request = try beginSignIn(userID: userID, serverID: serverID, validate: validate, validateSession: validateSession)
        try await signIn(request)
    }

    private func activateSignIn(
        _ request: SignInRequest,
        prepare: @MainActor (AsyncOperationGate.Checkpoint) async throws -> Void = { _ in },
        deepLink: DeepLink? = nil,
        reuseCurrent: Bool = false
    ) async throws {
        let session = reuseCurrent ? currentSession : request.session
        try await selections.activate(request.selection, with: session, prepare: prepare, willSelect: { checkpoint in
            try checkpoint()
            Defaults[.lastSignedInUserID] = .signedIn(userID: request.session.user.id)
            try checkpoint()
            self.metadataRefresh.cancel()
        }, didSelect: { checkpoint in
            try checkpoint()
            guard let session, self.currentSession === session else { throw CancellationError() }
            if !reuseCurrent {
                self.refreshServerInformationIfNeeded(reason: .explicitSignIn, session: session)
            }
            try checkpoint()
            if let deepLink {
                self.pendingDeepLink = deepLink
            }
        })
    }

    /// Synchronous submission keeps a queued sign-out tied to its original intent.
    func requestSignOut(reason: SignOutReason, didSignOut: @escaping @MainActor () -> Void = {}) {
        do {
            guard let request = try selections.begin(priority: .explicit) else { return }
            Task { @MainActor in
                do {
                    try await self.completeSignOut(reason: reason, request: request)
                    try request.check()
                    didSignOut()
                } catch is CancellationError { return
                } catch { self.logger.error("Unable to sign out", metadata: ["error": .string(error.localizedDescription)]) }
            }
        } catch { return }
    }

    func signOut(reason: SignOutReason, validate: @escaping AsyncOperationGate.Checkpoint) async throws {
        guard let request = try selections.begin(priority: .explicit, validate: validate) else { throw CancellationError() }
        try await completeSignOut(reason: reason, request: request)
    }

    private func completeSignOut(reason: SignOutReason, request: SelectionRequest) async throws {
        try await selections.activate(request, with: nil, willSelect: { checkpoint in
            try checkpoint()
            self.metadataRefresh.cancel()
            try checkpoint()
            Defaults[.lastSignedInUserID] = .signedOut
        }, didSelect: { checkpoint in
            try checkpoint()
            self.logger.info("Signed out current user", metadata: ["reason": .string(String(describing: reason))])
        })
    }

    private func stopActivePlayback(validate: AsyncOperationGate.Checkpoint) async throws {
        try validate()
        guard let manager = mediaPlayerManager else { return }
        await manager.stop()
        try validate()
        playerSelection.apply(.retired(manager))
    }

    func scheduleServerConnectionResolution() {
        currentSession?.serverConnectionManager.scheduleConnectionResolution()
    }

    func handleOpenURL(_ url: URL, authenticationAction: LocalUserAuthenticationAction) {
        guard let deepLink = DeepLink(url) else { return }
        do {
            let target = try session(for: deepLink)
            let request = try beginSignIn(userID: target.user.id, serverID: target.server.id)
            let sameAccount = currentSession?.sessionIdentity == request.session.sessionIdentity
            Task { @MainActor in
                do {
                    try await self.activateSignIn(request, prepare: { checkpoint in
                        if !sameAccount {
                            try await self.authenticate(
                                user: request.session.user,
                                policy: request.policy,
                                authenticationAction: authenticationAction,
                                validate: checkpoint
                            )
                            try checkpoint()
                            if self.hasActivePlayback {
                                try await self.stopActivePlayback(validate: checkpoint)
                            }
                        }
                    }, deepLink: deepLink, reuseCurrent: sameAccount)
                } catch is CancellationError { return
                } catch { self.logger.error("Failed to process deep link", metadata: ["error": .string(error.localizedDescription)]) }
            }
        } catch is CancellationError { return
        } catch { logger.error("Failed to process deep link", metadata: ["error": .string(error.localizedDescription)]) }
    }

    func consumePendingDeepLink() -> DeepLink? {
        defer { pendingDeepLink = nil }
        return pendingDeepLink
    }

    private func scheduleForegroundRestoration() {
        do {
            let expires = currentSession != nil && Defaults[.signOutOnBackground] && !hasActivePlayback &&
                Date.now.timeIntervalSince(Defaults[.backgroundTimeStamp]) > Defaults[.backgroundSignOutInterval]
            guard let request = try selections.begin(priority: .restoration, validate: { [weak self] in
                guard let self, !expires || !self.hasActivePlayback else { throw CancellationError() }
            }) else { return }
            Task { @MainActor in await self.restore(request, signOut: expires, refreshMetadata: true) }
        } catch { return }
    }

    private func restore(_ request: SelectionRequest, signOut: Bool, refreshMetadata: Bool) async {
        do {
            try request.check()
            let session: UserSession?
            var resetStamp = signOut
            do { session = signOut ? nil : try resolveStoredSession()
            } catch {
                try request.check()
                logger.error("Unable to resolve stored session", metadata: ["error": .string(error.localizedDescription)])
                resetStamp = true
                session = nil
            }
            try await selections.activate(request, with: session, willSelect: { checkpoint in
                try checkpoint()
                if resetStamp {
                    Defaults[.lastSignedInUserID] = .signedOut
                }
                try checkpoint()
                self.metadataRefresh.cancel()
            }, didSelect: { checkpoint in
                try checkpoint()
                if refreshMetadata, let session {
                    self.refreshServerInformationIfNeeded(reason: .stale, session: session)
                }
            })
        } catch is CancellationError { return
        } catch { logger.error("Unable to restore current session", metadata: ["error": .string(error.localizedDescription)]) }
    }

    private enum ServerInformationRefreshReason {
        case explicitSignIn
        case stale
    }

    private func session(for deepLink: DeepLink) throws -> (server: ServerState, user: UserState) {
        guard let server = StoredValues[.Server.servers].first(where: { $0.id == deepLink.serverID }) else {
            throw DeepLinkError.missingServer(deepLink.serverID)
        }

        guard let user = StoredValues[.User.users].first(where: { $0.id == deepLink.userID && $0.serverID == server.id }) else {
            throw DeepLinkError.missingUser(deepLink.userID)
        }

        return (server, user)
    }

    private func authenticate(
        user: UserState,
        policy: LocalUserAccessPolicy,
        authenticationAction: LocalUserAuthenticationAction,
        validate: AsyncOperationGate.Checkpoint
    ) async throws {
        try validate()
        guard policy != .none else { return }
        let evaluatedPolicy = try await authenticationAction(policy: policy, reason: policy.authenticateReason(user: user))
        try validate()
        if policy == .requirePin {
            guard let pinPolicy = evaluatedPolicy as? PinEvaluatedUserAccessPolicy,
                  try Container.shared.localAccountStore().matchesPIN(pinPolicy.pin, userID: user.id)
            else { throw ErrorMessage(L10n.incorrectPinForUser(user.username)) }
        }
        try validate()
    }

    @MainActor
    private func refreshServerInformationIfNeeded(reason: ServerInformationRefreshReason, session: UserSession) {
        let client = session.client
        let server = session.server
        let user = session.user
        let scope = MetadataRefreshID(serverID: server.id, userID: user.id, url: client.configuration.url)
        metadataRefresh.request(
            scope: scope,
            force: reason == .explicitSignIn,
            isCurrent: { [weak self, weak session, weak client] in
                guard let self, let session, let client else { return false }
                return currentSession === session && session.client === client
            },
            operation: { checkpoint in
                try await server.updateServerInfo(validate: checkpoint)
                try checkpoint()
                try await user.updateUserData(server: server, validate: checkpoint)
            },
            didRefresh: { date in
                // Preserve the installed legacy stamp; scheduling uses scoped freshness.
                Defaults[.lastServerInformationRefreshDate] = date
            },
            didFail: { [weak self] error in
                self?.logger.error(
                    "Unable to refresh server and user information",
                    metadata: ["error": .string(error.localizedDescription)]
                )
            }
        )
    }

    private func setupObservations() {
        Notifications[.applicationDidEnterBackground]
            .publisher
            .sink {
                Defaults[.backgroundTimeStamp] = Date.now
            }
            .store(in: &cancellables)

        Notifications[.applicationWillEnterForeground]
            .publisher
            .sink { [weak self] in
                self?.scheduleForegroundRestoration()
            }
            .store(in: &cancellables)

        Container.shared.mediaPlayerManagerPublisher()
            .sink { [weak self] event in self?.playerSelection.apply(event) }
            .store(in: &cancellables)

        observeSocketCommands()
    }

    private lazy var sessionCoordinator =
        ActiveSessionCoordinator<UserSession>(publishScoped: { [weak self] session, identityChanged, checkpoint in
            guard let self else { throw CancellationError() }
            try checkpoint()
            metadataRefresh.cancel()
            try checkpoint()
            currentSession = session
            try checkpoint()
            Container.shared.currentUserSession.reset()
            try checkpoint()
            if identityChanged {
                playerSelection.clear()
                try checkpoint()
                Container.shared.mediaPlayerManager.reset()
            }
            try checkpoint()
            state = session == nil ? .signedOut : .signedIn
            try checkpoint()
        })

    private lazy var selections = SessionSelectionCoordinator(sessions: sessionCoordinator)

    private func resolveStoredSession() throws -> UserSession? {
        guard case let .signedIn(userId) = Defaults[.lastSignedInUserID] else { return nil }

        guard let user = StoredValues[.User.users].first(where: { $0.id == userId }) else {
            throw UserSessionError.invalidStoredSession(userID: userId)
        }

        guard let server = StoredValues[.Server.servers].first(where: { $0.id == user.serverID }) else {
            throw UserSessionError.invalidStoredSession(userID: userId)
        }

        return .init(
            server: server,
            user: user
        )
    }
}
