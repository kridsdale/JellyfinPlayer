//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Combine
import Foundation
import os

/// Main-actor stream delivery with subscription-scoped, executor-independent
/// Combine cancellation. One publisher shares a stream while subscribers exist;
/// the last subscriber releases it. A later subscriber starts a fresh stream.
public enum AsyncStreamPublishers {
    @MainActor
    public static func shared<Value: Sendable>(
        _ makeStream: @escaping @MainActor () -> AsyncStream<Value>
    ) -> AnyPublisher<Value, Never> {
        let relay = StreamRelay(makeStream: makeStream)
        return deferredPublisher(source: relay.subject.eraseToAnyPublisher(), relay: relay)
    }
}

@MainActor
private final class StreamRelay<Value: Sendable> {
    let subject = PassthroughSubject<Value, Never>()
    private let makeStream: @MainActor () -> AsyncStream<Value>
    private var subscribers: Set<UUID> = []
    private var task: Task<Void, Never>?

    init(makeStream: @escaping @MainActor () -> AsyncStream<Value>) {
        self.makeStream = makeStream
    }

    func activate(_ id: UUID) {
        guard !Task.isCancelled else { return }
        subscribers.insert(id)
        guard task == nil else { return }
        let stream = makeStream()
        let output = subject
        task = Task {
            for await value in stream {
                guard !Task.isCancelled else { return }
                output.send(value)
            }
            if !Task.isCancelled {
                output.send(completion: .finished)
            }
        }
    }

    func release(_ id: UUID) {
        subscribers.remove(id)
        if subscribers.isEmpty {
            task?.cancel()
            task = nil
        }
    }

    isolated deinit { task?.cancel() }
}

/// Immutable references plus one checked, locked cancellation bit. No subscriber
/// or SDK object crosses executors. Combine invokes these callbacks on any queue.
private final class SubscriptionLease<Value: Sendable>: Sendable {
    private let activation: Task<Void, Never>
    private let relay: StreamRelay<Value>
    private let id: UUID
    private let released = OSAllocatedUnfairLock(initialState: false)

    init(activation: Task<Void, Never>, relay: StreamRelay<Value>, id: UUID) {
        self.activation = activation
        self.relay = relay
        self.id = id
    }

    func cancel() {
        guard released.withLock({ released in
            if released {
                return false
            }
            released = true
            return true
        }) else { return }
        activation.cancel()
        Task { @MainActor [activation, relay, id] in
            await activation.value
            relay.release(id)
        }
    }

    deinit { cancel() }
}

// Defined outside actor isolation so Combine never receives an actor-inheriting
// callback. Only activation/delivery/release explicitly enter the main actor.
private func deferredPublisher<Value: Sendable>(
    source: AnyPublisher<Value, Never>, relay: StreamRelay<Value>
) -> AnyPublisher<Value, Never> {
    Deferred {
        let id = UUID()
        let activation = Task { @MainActor in relay.activate(id) }
        let lease = SubscriptionLease(activation: activation, relay: relay, id: id)
        return source.handleEvents(
            receiveCompletion: { _ in lease.cancel() },
            receiveCancel: lease.cancel
        ).eraseToAnyPublisher()
    }.eraseToAnyPublisher()
}
