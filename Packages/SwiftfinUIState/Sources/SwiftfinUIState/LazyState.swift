//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import SwiftUI

@MainActor
@propertyWrapper
public struct LazyState<Value>: @MainActor DynamicProperty {

    private final class Box {

        private var value: Value!
        private let thunk: () -> Value
        var didThunk = false

        var wrappedValue: Value {
            value
        }

        func setup() {
            value = thunk()
            didThunk = true
        }

        init(wrappedValue thunk: @autoclosure @escaping () -> Value) {
            self.thunk = thunk
        }
    }

    @State
    private var holder: Box

    public var wrappedValue: Value {
        holder.wrappedValue
    }

    public var projectedValue: Binding<Value> {
        Binding(get: { wrappedValue }, set: { _ in })
    }

    public func update() {
        guard !holder.didThunk else { return }
        holder.setup()
    }

    public init(wrappedValue thunk: @autoclosure @escaping () -> Value) {
        _holder = State(wrappedValue: Box(wrappedValue: thunk()))
    }
}
