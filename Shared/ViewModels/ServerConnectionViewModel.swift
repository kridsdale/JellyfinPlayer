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
import SwiftfinAccountModels
import SwiftfinAccountStore
import SwiftfinAsyncStreams
import SwiftfinConnectivity
import SwiftfinText
import SwiftfinUIState

@MainActor
final class ServerConnectionViewModel: ViewModel {
    let server: ServerState
    @CommittedPublished
    private(set) var connections: [ServerConnection] {
        didSet { objectWillChange.send() }
    }

    @CommittedPublished
    private(set) var activeConnection: ServerConnection? {
        didSet { objectWillChange.send() }
    }

    @CommittedPublished
    private(set) var isEvaluatingAutoSwitchConnection = false {
        didSet { objectWillChange.send() }
    }

    @CommittedPublished
    private(set) var testStates: [String: ServerConnection.TestState] = [:] {
        didSet { objectWillChange.send() }
    }

    @CommittedPublished
    var isAutoSwitchEnabled: Bool {
        didSet {
            objectWillChange.send()
            guard oldValue != isAutoSwitchEnabled, Defaults[.Experimental.serverConnectionAutoSwitch],
                  (try? checkOrigin()) != nil else { return }
            store.setAutoSwitchEnabled(isAutoSwitchEnabled, serverID: server.id)
            if isAutoSwitchEnabled {
                manager.scheduleServerConnectionResolution()
            }
        }
    }

    private let store: LocalAccountStore
    private let manager: UserSessionManager
    private let originSessionID: ObjectIdentifier?
    private var tests: [String: AsyncOperationGate] = [:]
    private let evaluations = AsyncOperationGate()

    init(server: ServerState) {
        self.server = server
        store = Container.shared.localAccountStore()
        manager = Container.shared.userSessionManager()
        originSessionID = manager.currentSession.map(ObjectIdentifier.init)
        connections = store.ensureConnections(for: server)
        activeConnection = store.activeConnection(for: server)
        isAutoSwitchEnabled = store.autoSwitchEnabled(serverID: server.id)
        super.init()
        Notifications[.didChangeServerConnection].publisher.receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.reloadConnections() }.store(in: &cancellables)
    }

    private func checkOrigin() throws {
        try Task.checkCancellation()
        guard manager.currentSession.map(ObjectIdentifier.init) == originSessionID,
              store.servers.contains(where: { $0.id == server.id }) else { throw CancellationError() }
    }

    func delete() {
        guard (try? checkOrigin()) != nil else { return }
        do {
            tests.values.forEach { $0.cancel() }
            evaluations.cancel()
            try store.deleteServer(server)
            Notifications[.didDeleteServer].post(server)
        } catch { logger.critical("Unable to delete server: \(server.name)") }
    }

    func newConnection() -> ServerConnection {
        .init(id: UUID().uuidString, name: "", url: store.effectiveURL(for: server), interface: .any, priority: connections.count)
    }

    func deleteConnection(_ connection: ServerConnection) {
        edit(.delete(connection.id))
    }

    func moveConnections(fromOffsets offsets: IndexSet, toOffset destination: Int) {
        var moved = connections
        moved.move(fromOffsets: offsets, toOffset: destination)
        edit(.reorder(moved.map(\.id)))
    }

    private func edit(_ edit: ConnectionCatalogEdit) {
        do {
            try checkOrigin()
            let snapshot = try store.connectionCatalog(serverID: server.id)
            let updated = try store.editConnections(edit, snapshot: snapshot, validate: { [weak self] in
                guard let self else { throw CancellationError() }
                try checkOrigin()
            })
            try publish(updated)
        } catch { /* A removed server or retired view cannot mutate its catalog. */ }
    }

    private func publish(_ snapshot: ConnectionCatalogSnapshot) throws {
        try checkOrigin()
        try store.validateConnectionCatalog(snapshot)
        connections = snapshot.connections
        try checkOrigin()
        try store.validateConnectionCatalog(snapshot)
        activeConnection = snapshot.active
        try checkOrigin()
        try store.validateConnectionCatalog(snapshot)
        isAutoSwitchEnabled = snapshot.autoSwitchEnabled
    }

    private func probeToken() throws -> String? {
        guard let session = manager.currentSession, session.server.id == server.id else { return nil }
        return try store.accessToken(userID: session.user.id)
    }

    private func probe(_ connection: ServerConnection, edit: ConnectionCatalogEdit? = nil) async -> ServerConnection.TestState {
        var retire: AsyncOperationGate.Checkpoint?
        do {
            try checkOrigin()
            let snapshot = try store.connectionCatalog(serverID: server.id)
            let gate = tests[connection.id] ?? AsyncOperationGate()
            tests[connection.id] = gate
            let receipt = gate.begin()
            let scope: AsyncOperationGate.Checkpoint = { [weak self] in
                try receipt()
                guard let self else { throw CancellationError() }
                try checkOrigin()
                try receipt()
            }
            retire = scope
            let validate: AsyncOperationGate.Checkpoint = { [weak self] in
                try receipt()
                guard let self else { throw CancellationError() }
                try checkOrigin()
                try store.validateConnectionCatalog(snapshot)
                try receipt()
            }
            // Never send another server's credential to this endpoint.
            let token = try probeToken()
            try validate()
            testStates[connection.id] = .testing
            do {
                try validate()
                try await ServerConnectionManager.test(connection: connection, accessToken: token, matchingServerID: server.id)
                try validate()
                let updated = try edit.map { try store.editConnections($0, snapshot: snapshot, validate: scope) } ?? snapshot
                try receipt()
                try checkOrigin()
                try store.validateConnectionCatalog(updated)
                if edit != nil {
                    try publish(updated)
                }
                try receipt()
                try checkOrigin()
                try store.validateConnectionCatalog(updated)
                testStates[connection.id] = .success
                try receipt()
                try checkOrigin()
                try store.validateConnectionCatalog(updated)
                if updated.active != snapshot.active, let active = updated.active {
                    Notifications[.didChangeServerConnection].post(active)
                    try receipt()
                    try checkOrigin()
                    try store.validateConnectionCatalog(updated)
                }
                return .success
            } catch {
                try validate()
                let state = ServerConnection.TestState.failure(error.localizedDescription)
                testStates[connection.id] = state
                try validate()
                return state
            }
        } catch {
            if let retire, (try? retire()) != nil {
                testStates[connection.id] = .idle
            }
            return .idle
        }
    }

    func testConnection(_ connection: ServerConnection) async -> ServerConnection.TestState {
        await probe(connection)
    }

    func saveConnection(_ connection: ServerConnection) async -> ServerConnection.TestState {
        await probe(
            connection,
            edit: .upsert(connection)
        )
    }

    func setActiveConnectionIfValid(_ connection: ServerConnection) async {
        _ = await probe(connection, edit: .activate(connection))
    }

    func evaluateAutoSwitchConnection() async {
        guard Defaults[.Experimental.serverConnectionAutoSwitch], isAutoSwitchEnabled, !isEvaluatingAutoSwitchConnection,
              !manager.hasActivePlayback, (try? checkOrigin()) != nil else { return }
        let receipt = evaluations.begin()
        isEvaluatingAutoSwitchConnection = true
        // No successor evaluation can start while this flag is true.
        defer { isEvaluatingAutoSwitchConnection = false }
        do {
            try receipt()
            try checkOrigin()
            let snapshot = try store.connectionCatalog(serverID: server.id)
            let validate: AsyncOperationGate.Checkpoint = { [weak self] in
                try receipt()
                guard let self else { throw CancellationError() }
                try checkOrigin()
                try store.validateConnectionCatalog(snapshot)
                guard Defaults[.Experimental.serverConnectionAutoSwitch], isAutoSwitchEnabled,
                      !manager.hasActivePlayback else { throw CancellationError() }
            }
            let session = manager.currentSession
            let token = try probeToken()
            try validate()
            if let session, session.server.id == server.id {
                await session.serverConnectionManager.resolveActiveConnection()
                try receipt()
                try checkOrigin()
                reloadConnections()
            } else {
                let context = await NetworkConnectivity.current()
                try validate()
                let resolution = await ServerConnectionManager.evaluate(server: server, accessToken: token, context: context)
                try validate()
                if case let .connected(connection) = resolution {
                    let updated = try store.editConnections(.activate(connection), snapshot: snapshot, validate: { [weak self] in
                        try receipt()
                        guard let self else { throw CancellationError() }
                        try checkOrigin()
                        guard Defaults[.Experimental.serverConnectionAutoSwitch], isAutoSwitchEnabled,
                              !manager.hasActivePlayback else { throw CancellationError() }
                    })
                    try receipt()
                    try publish(updated)
                }
            }
        } catch { /* Retired native results do not publish settings or failures. */ }
    }

    private func reloadConnections() {
        guard (try? checkOrigin()) != nil, let snapshot = try? store.connectionCatalog(serverID: server.id) else { return }
        try? publish(snapshot)
    }
}
