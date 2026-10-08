//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation
import JellyfinAPI

public enum ServerSocketCommand: Sendable {
    case general(GeneralCommand)
    case play(PlayRequest)
    case playstate(PlaystateRequest)
}

@MainActor
protocol SocketSubscriptionLease: AnyObject { func cancel() }
@MainActor
protocol SocketSessionDriver: AnyObject {
    var events: AsyncThrowingStream<JellyfinSocket.Session.Event, any Error> { get }
    func subscribe(_ topic: JellyfinSocket.Subscription, delay: Duration, interval: Duration) -> any SocketSubscriptionLease
    func disconnect()
}

@MainActor
private final class SDKSocketSubscription: SocketSubscriptionLease {
    let token: JellyfinSocket.Session.SubscriptionToken
    init(_ token: JellyfinSocket.Session.SubscriptionToken) {
        self.token = token
    }

    func cancel() {
        token.cancel()
    }
}

@MainActor
private final class SDKSocketSession: SocketSessionDriver {
    let session: JellyfinSocket.Session
    init(_ session: JellyfinSocket.Session) {
        self.session = session
    }

    var events: AsyncThrowingStream<JellyfinSocket.Session.Event, any Error> {
        session.events
    }

    func subscribe(_ topic: JellyfinSocket.Subscription, delay: Duration, interval: Duration) -> any SocketSubscriptionLease {
        SDKSocketSubscription(session.subscribe(topic, delay: delay, interval: interval))
    }

    func disconnect() {
        session.disconnect()
    }
}

/// Owns native socket sessions, ordered reconnect/teardown and scoped claims.
/// Public consumers receive Sendable values/async streams, never SDK sessions,
/// tokens, native events or actor-inheriting Combine cancellation callbacks.
@MainActor
public final class JellyfinSocketController {
    private enum Payload: Sendable {
        case connection(Bool)
        case command(ServerSocketCommand)
        case sessions([SessionInfoDto])
        case activities([ActivityLogEntry])
        case tasks([TaskInfo])
    }

    private struct Listener {
        let topic: JellyfinSocket.Subscription?
        let delay: Duration
        let interval: Duration
        let emit: @MainActor (Payload) -> Void
        let finish: @MainActor () -> Void
        var token: (any SocketSubscriptionLease)?
    }

    private enum Next { case end, wake, backoff }
    private let sessionFactory: @MainActor () -> (any SocketSessionDriver)?
    private let backoff: @MainActor () async -> Void
    private let diagnostic: @MainActor (String) -> Void
    private var listeners: [UUID: Listener] = [:]
    private var session: (any SocketSessionDriver)?
    private var worker: Task<Void, Never>?
    private var wake: AsyncStream<Void>.Continuation?
    private var generation: UInt64 = 0
    private var reconnectRequested = false
    private var connected = false

    public convenience init(
        client: @escaping @MainActor () -> JellyfinTransport?,
        diagnostic: @escaping @MainActor (String) -> Void = { _ in }
    ) {
        self.init(sessionFactory: { client().map { SDKSocketSession($0.makeSocketSession()) } }, diagnostic: diagnostic)
    }

    init(
        sessionFactory: @escaping @MainActor () -> (any SocketSessionDriver)?,
        backoff: @escaping @MainActor () async -> Void = { try? await Task.sleep(for: .seconds(2)) },
        diagnostic: @escaping @MainActor (String) -> Void = { _ in }
    ) {
        self.sessionFactory = sessionFactory
        self.backoff = backoff
        self.diagnostic = diagnostic
    }

    public func start() {
        let attempt = generation &+ 1
        stop()
        guard generation == attempt else { return }
        let (stream, continuation) = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
        wake = continuation
        let delay = backoff
        worker = Task { [weak self] in
            await Self.run(owner: { [weak self] in self }, generation: attempt, wake: stream, backoff: delay)
        }
    }

    public func stop() {
        generation &+= 1
        let oldWorker = worker
        let oldWake = wake
        let oldSession = session
        let oldClaims = detachClaims()
        worker = nil
        wake = nil
        session = nil
        reconnectRequested = false
        setConnected(false)
        // Publish retirement before native callbacks can install a replacement.
        oldWorker?.cancel()
        oldWake?.finish()
        oldSession?.disconnect()
        for claim in oldClaims {
            claim.cancel()
        }
    }

    public func reconnect() {
        let attempt = generation
        let current = session
        let signal = wake
        reconnectRequested = true
        current?.disconnect()
        guard generation == attempt else { return }
        signal?.yield()
    }

    private func detachClaims() -> [any SocketSubscriptionLease] {
        let claims = listeners.values.compactMap(\.token)
        for id in Array(listeners.keys) {
            listeners[id]?.token = nil
        }
        return claims
    }

    public func connectionStates() -> AsyncStream<Bool> {
        let current = connected
        return register(initial: current) {
            if case let .connection(value) = $0 {
                value
            } else {
                nil
            }
        }
    }

    public func commands() -> AsyncStream<ServerSocketCommand> {
        register(bufferingPolicy: .unbounded) {
            if case let .command(value) = $0 {
                value
            } else {
                nil
            }
        }
    }

    public func sessions(delay: Duration = .seconds(2), interval: Duration = .seconds(2)) -> AsyncStream<[SessionInfoDto]> {
        register(topic: .sessions, delay: delay, interval: interval) {
            if case let .sessions(value) = $0 {
                value
            } else {
                nil
            }
        }
    }

    public func activityLog(delay: Duration = .seconds(0), interval: Duration = .seconds(5)) -> AsyncStream<[ActivityLogEntry]> {
        register(topic: .activityLog, delay: delay, interval: interval) {
            if case let .activities(value) = $0 {
                value
            } else {
                nil
            }
        }
    }

    public func scheduledTasks(delay: Duration = .seconds(0), interval: Duration = .seconds(5)) -> AsyncStream<[TaskInfo]> {
        register(topic: .scheduledTasks, delay: delay, interval: interval) {
            if case let .tasks(value) = $0 {
                value
            } else {
                nil
            }
        }
    }

    private func register<Value: Sendable>(
        topic: JellyfinSocket.Subscription? = nil,
        delay: Duration = .zero, interval: Duration = .zero,
        initial: Value? = nil,
        bufferingPolicy: AsyncStream<Value>.Continuation.BufferingPolicy = .bufferingNewest(1),
        extract: @escaping @MainActor (Payload) -> Value?
    ) -> AsyncStream<Value> {
        let id = UUID()
        let (stream, continuation) = AsyncStream<Value>.makeStream(bufferingPolicy: bufferingPolicy)
        listeners[id] = Listener(topic: topic, delay: delay, interval: interval, emit: {
            if let value = extract($0) {
                continuation.yield(value)
            }
        }, finish: { continuation.finish() })
        if let initial {
            continuation.yield(initial)
        }
        if let topic, let session {
            let attempt = generation
            let token = session.subscribe(topic, delay: delay, interval: interval)
            if generation == attempt, self.session === session, listeners[id] != nil {
                listeners[id]?.token = token
            } else {
                token.cancel()
            }
        } else if topic != nil {
            wake?.yield()
        }
        continuation.onTermination = { [weak self] _ in
            Task { @MainActor [weak self] in self?.removeListener(id) }
        }
        return stream
    }

    private func removeListener(_ id: UUID) {
        let retired = listeners.removeValue(forKey: id)
        retired?.token?.cancel()
    }

    private func emit(_ payload: Payload) {
        for listener in listeners.values {
            listener.emit(payload)
        }
    }

    private func setConnected(_ value: Bool) {
        connected = value
        emit(.connection(value))
    }

    private func owns(_ attempt: UInt64, driver: any SocketSessionDriver) -> Bool {
        generation == attempt && session === driver && !Task.isCancelled
    }

    private func retireIfOwned(_ attempt: UInt64, driver: any SocketSessionDriver) {
        guard generation == attempt, session === driver else { return }
        stop()
    }

    private func begin(_ attempt: UInt64) -> (any SocketSessionDriver)? {
        guard generation == attempt, !Task.isCancelled, let next = sessionFactory() else { return nil }
        guard generation == attempt, !Task.isCancelled else {
            next.disconnect()
            return nil
        }
        session = next
        let registrations = listeners
        for (id, listener) in registrations {
            guard let topic = listener.topic, listeners[id] != nil else { continue }
            let token = next.subscribe(topic, delay: listener.delay, interval: listener.interval)
            guard owns(attempt, driver: next) else {
                token.cancel()
                retireIfOwned(attempt, driver: next)
                return nil
            }
            if listeners[id] != nil {
                listeners[id]?.token = token
            } else {
                token.cancel()
            }
        }
        diagnostic("Socket connecting")
        guard owns(attempt, driver: next) else {
            retireIfOwned(attempt, driver: next)
            return nil
        }
        return next
    }

    private func receive(_ event: JellyfinSocket.Session.Event, generation attempt: UInt64) -> Bool {
        guard generation == attempt, !Task.isCancelled else { return false }
        switch event {
        case .connecting: diagnostic("Socket retrying")
        case .connected: setConnected(true)
        case .disconnected: setConnected(false)
        case let .message(message):
            switch message {
            case let .generalCommandMessage(value): if let payload = value.data {
                    emit(.command(.general(payload)))
                }
            case let .playMessage(value): if let payload = value.data {
                    emit(.command(.play(payload)))
                }
            case let .playstateMessage(value): if let payload = value.data {
                    emit(.command(.playstate(payload)))
                }
            case let .sessionsMessage(value): if let payload = value.data {
                    emit(.sessions(payload))
                }
            case let .activityLogEntryMessage(value): if let payload = value.data {
                    emit(.activities(payload))
                }
            case let .scheduledTasksInfoMessage(value): if let payload = value.data {
                    emit(.tasks(payload))
                }
            default: break
            }
        }
        return generation == attempt && !Task.isCancelled
    }

    private func ended(_ attempt: UInt64, refused: Bool) -> Next {
        guard generation == attempt, !Task.isCancelled else { return .end }
        session = nil
        let oldClaims = detachClaims()
        setConnected(false)
        let explicit = reconnectRequested
        reconnectRequested = false
        for claim in oldClaims {
            claim.cancel()
        }
        guard generation == attempt, !Task.isCancelled else { return .end }
        if explicit {
            return .wake
        }
        if listeners.values.contains(where: { $0.topic != nil }), !refused {
            return .backoff
        }
        return .wake
    }

    private static func run(
        owner: @escaping @MainActor () -> JellyfinSocketController?,
        generation: UInt64, wake: AsyncStream<Void>, backoff: @MainActor () async -> Void
    ) async {
        var signals = wake.makeAsyncIterator()
        while !Task.isCancelled {
            guard let driver = owner()?.begin(generation) else { return }
            var refused = false
            do {
                for try await event in driver.events {
                    guard owner()?.receive(event, generation: generation) == true else { driver.disconnect()
                        return
                    }
                }
            } catch {
                if let error = error as? JellyfinSocket.Session.SocketError, case .unauthorized = error {
                    refused = true
                }
            }
            switch owner()?.ended(generation, refused: refused) ?? .end {
            case .end: return
            case .wake: guard await signals.next() != nil else { return }
            case .backoff: await backoff()
            }
        }
    }

    isolated deinit {
        stop()
        for listener in listeners.values {
            listener.finish()
        }
    }
}
