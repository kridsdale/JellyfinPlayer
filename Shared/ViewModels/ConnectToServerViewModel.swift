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
import Logging
import OrderedCollections
import StatefulMacros
import SwiftfinAccountAccess
import SwiftfinAccountModels
import SwiftfinAccountStore
import SwiftfinAsyncStreams
import SwiftfinCollections
import SwiftfinLocalization
import SwiftfinNetworking
import SwiftfinText
import SwiftfinUIState

@MainActor
@Stateful
final class ConnectToServerViewModel: ObservableObject {
    struct Request: Sendable { let validate: AsyncOperationGate.Checkpoint }
    @CasePathable
    enum Action {
        case runAdd(Request, ServerState)
        case cancel
        case runConnect(Request, String)
        case runDiscovery(Request)
        var transition: Transition {
            switch self {
            case .runAdd, .runDiscovery: .none
            case .cancel: .to(.initial)
            case .runConnect: .loop(.connecting)
            }
        }
    }

    enum Event {
        case connected(ServerState)
        case duplicateServer(ServerState)
        case error
    }

    enum State { case connecting, initial }
    @CommittedPublished
    var localServers: OrderedSet<ServerState> = [] {
        didSet { objectWillChange.send() }
    }

    let logger = Logger.swiftfin()
    var cancellables = Set<AnyCancellable>()
    private let store = Container.shared.localAccountStore()
    private let originSessionID = Container.shared.userSessionManager().currentSession.map(ObjectIdentifier.init)
    private let admissions = AsyncOperationGate()
    private let discoveries = AsyncOperationGate()

    private func checkOrigin() throws {
        try Task.checkCancellation()
        guard Container.shared.userSessionManager().currentSession.map(ObjectIdentifier.init) == originSessionID
        else { throw CancellationError() }
    }

    private func request(_ gate: AsyncOperationGate) -> Request? {
        guard (try? checkOrigin()) != nil else { return nil }
        let receipt = gate.begin()
        return .init(validate: { [weak self] in
            try receipt()
            guard let self else { throw CancellationError() }
            try checkOrigin()
            try receipt()
        })
    }

    func connect(url: String) {
        if let request = request(admissions) {
            runConnect(request, url)
        }
    }

    func addConnection(serverState: ServerState) {
        if let request = request(admissions) {
            runAdd(request, serverState)
        }
    }

    func searchForServers() {
        if let request = request(discoveries) {
            runDiscovery(request)
        }
    }

    @Function(\Action.Cases.cancel)
    private func _cancel() async {
        admissions.cancel()
        discoveries.cancel()
    }

    @Function(\Action.Cases.runConnect)
    private func _runConnect(_ request: Request, _ input: String) async throws {
        do {
            try request.validate()
            let formatted = input.trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: .objectReplacement).trimmingCharacters(in: ["/"])
                .prepending("http://", if: !input.contains("://"))
            guard let parsed = URL(string: formatted), parsed.host != nil else { throw ErrorMessage(L10n.invalidURL) }
            let url = ServerConnection.normalizedURL(parsed) ?? parsed
            let client = JellyfinTransport.swiftfin(url: url, policy: .systemDefault)
            let response = try await AccountAccessClient(transport: client).publicInfo()
            try request.validate()
            guard let name = response.value.serverName, let id = response.value.id else {
                logger.critical("Missing server data from network call")
                throw ErrorMessage(L10n.unknownError)
            }
            let redirected = AccountConnectionPolicy.redirectedURL(initial: url, response: response.responseURL)
            let endpoint = ServerConnection.normalizedURL(redirected) ?? redirected
            let server = ServerState(urls: [endpoint], currentURL: endpoint, name: name, id: id, userIDs: [])
            let registered = try store.registerServer(server, info: response.value, validate: request.validate)
            try request.validate()
            events.send(registered ? .connected(server) : .duplicateServer(server))
        } catch { try request.validate()
            throw error
        }
    }

    @Function(\Action.Cases.runAdd)
    private func _runAdd(_ request: Request, _ server: ServerState) async throws {
        do {
            try request.validate()
            let connection = try store.addConnection(url: server.currentURL, serverID: server.id, validate: request.validate)
            try request.validate()
            Notifications[.didChangeServerConnection].post(connection)
        } catch { try request.validate()
            throw error
        }
    }

    @Function(\Action.Cases.runDiscovery)
    private func _runDiscovery(_ request: Request) async {
        do {
            try request.validate()
            for try await server in JellyfinTransport.discover() {
                try request.validate()
                localServers.append(.init(urls: [server.url], currentURL: server.url, name: server.name, id: server.id, userIDs: []))
                try request.validate()
            }
        } catch {
            guard (try? request.validate()) != nil else { return }
            logger.error("Local server discovery failed: \(error.localizedDescription)")
        }
    }
}
