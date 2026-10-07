//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import CasePaths
import Combine
import Defaults
import Foundation
import JellyfinAPI
import Logging
import Pulse
import StatefulMacros
import SwiftfinAccountAccess
import SwiftfinAccountModels
import SwiftfinAsyncStreams
import SwiftfinConnections
import SwiftfinConnectivity
import SwiftfinLocalization
import SwiftfinNetworking
import SwiftfinText
import SwiftfinTime

@MainActor
@Stateful
final class ServerConnectionManager: ObservableObject {

    @CasePathable
    enum Action {
        case resolveActiveConnection
        case scheduleConnectionResolution
        case start
        case stop

        case _resolutionDidUpdate(Resolution)

        var transition: Transition {
            switch self {
            case .scheduleConnectionResolution, .start:
                .none
            case .resolveActiveConnection:
                .to(.evaluating)
            case let ._resolutionDidUpdate(.connected(connection)):
                .to(.connected(connection))
            case let ._resolutionDidUpdate(.unreachable(connections)):
                .to(.unreachable(connections))
            case .stop:
                .to(.initial)
            }
        }
    }

    enum State: Equatable {
        case initial
        case evaluating
        case connected(ServerConnection)
        case unreachable([ServerConnection])
    }

    typealias Resolution = ServerConnectionResolution

    private weak var userSession: UserSession?
    private var observation: NetworkContextObservation?
    private var observationTask: Task<Void, Never>?
    private var isStarted = false
    private var context: NetworkConnectionContext = .unavailable
    private var evaluationTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()

    static func test(
        connection: ServerConnection,
        accessToken: String? = nil,
        matchingServerID serverID: String
    ) async throws {
        do {
            try await ServerConnectionResolver.test(
                connection: connection, accessToken: accessToken,
                expectedServerID: serverID, probe: JellyfinServerConnectionProbe()
            )
        } catch ServerConnectionProbeError.serverMismatch {
            throw ErrorMessage(L10n.connectionServerMismatch)
        }
    }

    @MainActor
    static func evaluate(
        server: ServerState,
        accessToken: String?,
        context: NetworkConnectionContext
    ) async -> Resolution {
        // Legacy records may not yet have persisted connection IDs. Initialize
        // them once so the post-await snapshot comparison uses stable identities.
        let connections = server.ensureServerConnections()
        do {
            let resolution = try await ServerConnectionResolver.resolve(
                connections: connections, accessToken: accessToken,
                expectedServerID: server.id, context: context,
                probe: JellyfinServerConnectionProbe()
            )
            guard !Task.isCancelled, server.serverConnections == connections else {
                return .unreachable(server.serverConnections.filter { $0.matches(context) })
            }
            return resolution
        } catch {
            return .unreachable(connections.filter { $0.matches(context) })
        }
    }

    @Function(\Action.Cases.start)
    private func _start() async {
        MainActor.preconditionIsolated()
        guard !isStarted, userSession != nil else { return }
        isStarted = true

        let observation = NetworkContextObservation()
        self.observation = observation
        let values = observation.values
        observationTask = Task { [weak self] in
            for await newContext in values {
                guard !Task.isCancelled else { return }
                self?.contextDidUpdate(newContext)
            }
        }

        // TODO: determine if should be part of connection resolution
        //       - probably a bit too greedy
//        Notifications[.applicationWillEnterForeground]
//            .publisher
//            .sink { [weak self] in
//                Task { @MainActor in
//                    self?.scheduleConnectionResolution()
//                }
//            }
//            .store(in: &cancellables)
    }

    @Function(\Action.Cases.stop)
    private func _stop() async {
        MainActor.preconditionIsolated()
        guard isStarted else { return }

        isStarted = false
        evaluationTask?.cancel()
        evaluationTask = nil
        cancellables.removeAll()
        observationTask?.cancel()
        observationTask = nil
        observation?.cancel()
        observation = nil
        context = .unavailable
    }

    @Function(\Action.Cases.scheduleConnectionResolution)
    private func _scheduleConnectionResolution() async {
        MainActor.preconditionIsolated()
        guard isAutoSwitchEnabled else { return }

        evaluationTask?.cancel()
        evaluationTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }
            await self?.resolveActiveConnection()
        }
    }

    @Function(\Action.Cases.resolveActiveConnection)
    private func _resolveActiveConnection() async {
        guard !Task.isCancelled, isAutoSwitchEnabled, let userSession else { return }

        if context == .unavailable {
            context = await NetworkConnectivity.current()
            guard !Task.isCancelled else { return }
        }

        let currentConnection = userSession.server.activeServerConnection
        let requestedContext = context
        let resolution = await Self.evaluate(
            server: userSession.server,
            accessToken: userSession.user.accessToken,
            context: requestedContext
        )
        guard !Task.isCancelled, isAutoSwitchEnabled,
              self.userSession === userSession, context == requestedContext else { return }

        if case let .connected(reachableConnection) = resolution,
           currentConnection?.id != reachableConnection.id
        {
            userSession.server.activeServerConnection = reachableConnection
            Notifications[.didChangeServerConnection].post(reachableConnection)
        }

        await _resolutionDidUpdate(resolution)
    }

    @Function(\Action.Cases._resolutionDidUpdate)
    private func __resolutionDidUpdate(_ resolution: Resolution) async {
        MainActor.preconditionIsolated()
        // no-op, just for state transition
    }

    private func contextDidUpdate(_ context: NetworkConnectionContext) {
        let didChange = context != self.context && context.isSatisfied
        self.context = context

        if didChange, let connection = userSession?.server.activeServerConnection {
            Notifications[.didChangeServerConnection].post(connection)
        }

        scheduleConnectionResolution()
    }

    private var isAutoSwitchEnabled: Bool {
        guard let userSession else { return false }
        return Defaults[.Experimental.serverConnectionAutoSwitch] && userSession.server.isAutoSwitchEnabled
    }
}

extension ServerConnectionManager: UserSessionService {

    func willStart(userSession: UserSession) async {
        self.userSession = userSession

        await resolveActiveConnection()
    }

    func didStart(userSession: UserSession) {
        start()
    }

    func willStop() {
        self.userSession = nil
        evaluationTask?.cancel()
        stop()
    }
}

/// SDK transport adapter. Selection, interface policy and server-ID comparison
/// live in SwiftfinConnections; settings/session publication stays with the host.
@MainActor
private struct JellyfinServerConnectionProbe: ServerConnectionProbing {
    private static let logger = Logger.swiftfin()

    func serverID(at connection: ServerConnection, accessToken: String?) async throws -> String? {
        let client = JellyfinTransport.swiftfin(url: connection.url, accessToken: accessToken, policy: .connectionProbe)
        do {
            return try await AccountAccessClient(transport: client).publicInfo().value.id
        } catch {
            Self.logger.info("Server connection probe failed")
            throw error
        }
    }
}
