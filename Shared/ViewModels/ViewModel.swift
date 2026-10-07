//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Combine
import FactoryKit
import Foundation
import JellyfinAPI
import Logging
import SwiftfinAsyncStreams
import SwiftfinFilters
import SwiftfinItemMetadata
import SwiftfinMediaCatalog
import SwiftfinNetworking
import SwiftfinRecordingTimers
import SwiftfinServerOperations
import SwiftfinUserAdministration

@MainActor
class ViewModel: ObservableObject {

    let logger = Logger.swiftfin()

    /// The current signed-in user session, if the app is authenticated.
    @Injected(\.currentUserSession)
    var userSession: UserSession?

    var cancellables = Set<AnyCancellable>()

    init() {
        Notifications[.didChangeServerConnection]
            .publisher
            .sink { [weak self] _ in
                self?.$userSession.resolve(reset: .scope)
            }
            .store(in: &cancellables)
    }

    func requireUserSession() throws -> UserSession {
        guard let userSession else {
            logger.error("Missing user session for authenticated view model")
            throw UserSessionError.missingCurrentSession
        }

        return userSession
    }

    var authenticatedClient: JellyfinTransport {
        get throws {
            try requireUserSession().client
        }
    }

    var authenticatedServer: ServerState {
        get throws {
            try requireUserSession().server
        }
    }

    var authenticatedUser: UserState {
        get throws {
            try requireUserSession().user
        }
    }
}

extension ViewModel {
    private func administrationExecutor(for session: UserSession) -> AuthenticatedRequestExecutor {
        let client = session.client
        let manager = Container.shared.userSessionManager()
        return AuthenticatedRequestExecutor(sender: client, isCurrent: { [weak session, weak client, weak manager] in
            guard let session, let client, let manager else { return false }
            return manager.currentSession === session && session.client === client
        })
    }

    func requireServerOperations() throws -> ServerOperationsClient {
        let session = try requireUserSession()
        return ServerOperationsClient(executor: administrationExecutor(for: session), deviceID: session.client.configuration.deviceID)
    }

    func requireUserAdministration() throws -> UserAdministrationClient {
        let session = try requireUserSession()
        return UserAdministrationClient(executor: administrationExecutor(for: session), currentUserID: session.user.id)
    }
}

extension ViewModel {
    func requireRecordingTimers(item: BaseItemDto) throws -> RecordingTimersClient {
        let session = try requireUserSession()
        return RecordingTimersClient(
            executor: administrationExecutor(for: session),
            userID: session.user.id,
            item: item,
            permission: { [weak session] in session?.user.data.policy?.enableLiveTvManagement == true }
        )
    }

    func requireQueryFilters() throws -> QueryFiltersClient {
        let session = try requireUserSession()
        return QueryFiltersClient(executor: administrationExecutor(for: session), userID: session.user.id)
    }

    func requireMediaCatalog() throws -> MediaCatalogClient {
        try requireUserSession().mediaCatalog
    }

    func requireItemMetadata() throws -> ItemMetadataClient {
        try requireUserSession().itemMetadata
    }
}
