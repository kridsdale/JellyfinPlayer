//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Combine
import SwiftUI

@MainActor
@propertyWrapper
public struct BoxedPublished<Value>: @MainActor DynamicProperty {

    @StateObject
    var storage: PublishedBox<Value>

    public init(wrappedValue: Value) {
        self._storage = StateObject(wrappedValue: PublishedBox(initialValue: wrappedValue))
    }

    public var wrappedValue: Value {
        get { storage.value }
        nonmutating set { storage.value = newValue }
    }

    public var projectedValue: Published<Value>.Publisher {
        storage.$value
    }

    public var box: PublishedBox<Value> {
        storage
    }
}
