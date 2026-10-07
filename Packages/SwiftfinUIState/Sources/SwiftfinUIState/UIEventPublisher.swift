//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Combine

/// Transient UI events are delivered synchronously on their UI owner.
/// Copies share one subject; values are neither retained nor replayed.
@MainActor
public struct UIEventPublisher<Value>: @MainActor Publisher {
    public typealias Output = Value
    public typealias Failure = Never
    private let subject = PassthroughSubject<Value, Never>()

    public nonisolated init() {}

    public func receive<S: Subscriber>(subscriber: S) where S.Failure == Never, S.Input == Value {
        subject.receive(subscriber: subscriber)
    }

    public func send(_ value: Value) {
        subject.send(value)
    }
}
