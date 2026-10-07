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
import OrderedCollections
import StatefulMacros
import SwiftfinAsyncStreams
import SwiftfinCollections
import SwiftfinServerOperations

@MainActor
@Stateful
final class ActiveSessionsViewModel: ViewModel {

    struct Environment: WithDefaultValue {
        var activeWithinSeconds: Int?
        var showSessionType: ActiveSessionFilter
        var isPaused: Bool

        static var `default`: Self {
            .init(
                activeWithinSeconds: 900,
                showSessionType: .all,
                isPaused: false
            )
        }
    }

    @CasePathable
    enum Action {
        case refresh

        var transition: Transition {
            .to(.initial, then: .content)
                .whenBackground(.refreshing)
        }
    }

    enum BackgroundState {
        case refreshing
    }

    enum State {
        case content
        case error
        case initial
    }

    @Published
    var environment: Environment = .default {
        didSet {
            guard environment.activeWithinSeconds != oldValue.activeWithinSeconds ||
                environment.showSessionType != oldValue.showSessionType
            else {
                return
            }

            self.background.refresh()
        }
    }

    @Published
    private(set) var sessions: OrderedDictionary<String, SessionViewModel> = [:]

    private let sessionUpdates = ScopedPublisher<[ObjectIdentifier], [SessionInfoDto]>()

    override init() {
        super.init()

        Container.shared.userSessionManager()
            .$currentSession
            .sink { [weak self] session in self?.bindUpdates(to: session) }
            .store(in: &cancellables)

        Notifications[.didChangeServerConnection]
            .publisher
            .sink { [weak self] _ in
                self?.bindUpdates(to: Container.shared.userSessionManager().currentSession)
            }
            .store(in: &cancellables)
    }

    private func bindUpdates(to session: UserSession?) {
        guard let session else {
            sessionUpdates.cancel()
            sessions = [:]
            return
        }
        let client = session.client
        let manager = Container.shared.userSessionManager()
        let changed = sessionUpdates.replace(
            scope: [ObjectIdentifier(session), ObjectIdentifier(client)],
            makePublisher: { session.serverSocketManager.sessions() },
            isCurrent: { [weak session, weak client, weak manager] in
                guard let session, let client, let manager else { return false }
                return manager.currentSession === session && session.client === client
            },
            receive: { [weak self] values in self?.updateSessions(values) }
        )
        if changed {
            sessions = [:]
        }
    }

    @Function(\Action.Cases.refresh)
    private func _refresh() async throws {
        let values = try await requireServerOperations().sessions(activeWithinSeconds: environment.activeWithinSeconds)
        updateSessions(values)
    }

    private func updateSessions(_ incomingSessions: [SessionInfoDto]) {

        guard !environment.isPaused else {
            logger.debug("Socket updates are paused")
            return
        }

        // Reuse existing observers so ActiveSessionDetailsViews keep receiving updates
        var updatedSessions: OrderedDictionary<String, SessionViewModel> = [:]

        let filteredSessions = ServerOperationsPolicy.sessions(
            incomingSessions,
            activeWithinSeconds: environment.activeWithinSeconds,
            filter: ServerSessionFilter(rawValue: environment.showSessionType.rawValue) ??
                .all,
            now: .now
        )

        for session in filteredSessions {
            guard let id = session.id else { continue }

            if let existing = sessions[id] {
                existing.session = session
                updatedSessions[id] = existing
            } else {
                updatedSessions[id] = SessionViewModel(session: session)
            }
        }

        sessions = updatedSessions
    }
}
