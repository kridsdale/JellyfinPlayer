//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Combine
import Foundation
import JellyfinAPI
import Logging
import SwiftfinAsyncStreams
import SwiftfinNetworking

/// App session binding and legacy presentation publishers. Native socket
/// sessions, reconnect state and subscription leases belong to Networking.
@MainActor
final class ServerSocketManager {
    let isConnected = CurrentValueSubject<Bool, Never>(false)
    private let general = PassthroughSubject<GeneralCommand, Never>()
    private let play = PassthroughSubject<PlayRequest, Never>()
    private let playstate = PassthroughSubject<PlaystateRequest, Never>()
    private let logger = Logger.swiftfin()
    private weak var userSession: UserSession?
    private var tasks: [Task<Void, Never>] = []
    private lazy var controller = JellyfinSocketController(
        client: { [weak self] in self?.userSession?.client },
        diagnostic: { [weak self] message in self?.logger.debug("\(message)") }
    )

    var generalCommands: AnyPublisher<GeneralCommand, Never> {
        general.eraseToAnyPublisher()
    }

    var playCommands: AnyPublisher<PlayRequest, Never> {
        play.eraseToAnyPublisher()
    }

    var playstateCommands: AnyPublisher<PlaystateRequest, Never> {
        playstate.eraseToAnyPublisher()
    }

    private func start() {
        stop()
        guard userSession != nil else { return }
        let commands = controller.commands()
        let connections = controller.connectionStates()
        tasks = [
            Task { [weak self] in
                for await value in connections {
                    guard !Task.isCancelled else { return }
                    self?.isConnected.send(value)
                }
            },
            Task { [weak self] in
                for await command in commands {
                    guard !Task.isCancelled else { return }
                    switch command {
                    case let .general(value): self?.general.send(value)
                    case let .play(value): self?.play.send(value)
                    case let .playstate(value): self?.playstate.send(value)
                    }
                }
            },
            Task { [weak self] in
                for await _ in Notifications[.didChangeServerConnection].publisher.values {
                    guard !Task.isCancelled else { return }
                    self?.controller.reconnect()
                }
            }
        ]
        controller.start()
    }

    private func stop() {
        tasks.forEach { $0.cancel() }
        tasks.removeAll()
        controller.stop()
        isConnected.send(false)
    }

    func sessions(delay: Duration = .seconds(2), interval: Duration = .seconds(2)) -> AnyPublisher<[SessionInfoDto], Never> {
        AsyncStreamPublishers.shared { [weak self] in
            self?.controller.sessions(delay: delay, interval: interval) ?? AsyncStream { $0.finish() }
        }
    }

    func activityLog(delay: Duration = .seconds(0), interval: Duration = .seconds(5)) -> AnyPublisher<[ActivityLogEntry], Never> {
        AsyncStreamPublishers.shared { [weak self] in
            self?.controller.activityLog(delay: delay, interval: interval) ?? AsyncStream { $0.finish() }
        }
    }

    func scheduledTasks(delay: Duration = .seconds(0), interval: Duration = .seconds(5)) -> AnyPublisher<[TaskInfo], Never> {
        AsyncStreamPublishers.shared { [weak self] in
            self?.controller.scheduledTasks(delay: delay, interval: interval) ?? AsyncStream { $0.finish() }
        }
    }

    isolated deinit { stop() }
}

extension ServerSocketManager: UserSessionService {
    func willStart(userSession: UserSession) async {
        self.userSession = userSession
    }

    func didStart(userSession: UserSession) {
        start()
    }

    func willStop() {
        userSession = nil
        stop()
    }
}
