//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import SwiftfinStoredValues
import SwiftUI

/// A property wrapper for a stored `AnyData` object.
@MainActor
@propertyWrapper
public struct StoredValue<Value: Storable>: @MainActor DynamicProperty {

    @ObservedObject
    private var observable: StoredValueObservation<Value>

    public let key: StoredValues.Key<Value>

    public var projectedValue: Binding<Value> {
        $observable.value
    }

    public var wrappedValue: Value {
        get {
            observable.value
        }
        nonmutating set {
            observable.value = newValue
        }
    }

    public init(_ key: StoredValues.Key<Value>) {
        self.key = key
        self.observable = .init(key)
    }

    public mutating func update() {
        _observable.update()
    }
}
