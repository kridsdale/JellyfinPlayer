//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Combine

/// UI-actor values are committed before subscribers run. A reentrant assignment
/// supersedes delivery of an older value to remaining subscribers. Publishers
/// are for UI-actor composition; foreign callbacks use the scoped stream bridge.
@MainActor
@propertyWrapper
public final class CommittedPublished<Value: Equatable & Sendable> {
    private var value: Value
    private let subject: CurrentValueSubject<Value, Never>

    public init(wrappedValue: Value) {
        value = wrappedValue
        subject = CurrentValueSubject(wrappedValue)
    }

    public var wrappedValue: Value {
        get { value }
        set {
            value = newValue
            subject.send(newValue)
        }
    }

    public var projectedValue: AnyPublisher<Value, Never> {
        subject.filter { [weak self] in self?.value == $0 }.eraseToAnyPublisher()
    }
}
