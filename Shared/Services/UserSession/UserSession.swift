//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation
import JellyfinAPI
import Pulse
import SwiftfinNetworking
import SwiftfinSessions

@MainActor
final class UserSession: AccountSessionLifecycle {

    let server: ServerState
    let user: UserState

    lazy var client = JellyfinTransport.swiftfin(url: server.effectiveServerURL, accessToken: user.accessToken)

    @MainActor
    lazy var serverConnectionManager = ServerConnectionManager()

    lazy var serverSocketManager = ServerSocketManager()

    private lazy var lifecycle = SessionLifecycle(resources: [
        BoundSessionResource(session: self, service: serverConnectionManager),
        BoundSessionResource(session: self, service: serverSocketManager)
    ])

    var sessionIdentity: AccountSessionIdentity {
        .init(serverID: server.id, userID: user.id)
    }

    init(
        server: ServerState,
        user: UserState
    ) {
        self.server = server
        self.user = user
    }

    func prepare() async {
        await lifecycle.prepare()
    }

    func start() {
        lifecycle.start()
    }

    func stop() {
        lifecycle.stop()
    }
}

/// App composition binds a concrete session to existing services. The lifecycle
/// library only sees prepare/start/stop ports and never captures an app global.
@MainActor
private final class BoundSessionResource: SessionResource {
    private weak var session: UserSession?
    private let service: any UserSessionService
    init(session: UserSession, service: any UserSessionService) {
        self.session = session
        self.service = service
    }

    func prepare() async {
        guard let session else { return }
        await service.willStart(userSession: session)
    }

    func start() {
        guard let session else { return }
        service.didStart(userSession: session)
    }

    func stop() {
        service.willStop()
    }
}
