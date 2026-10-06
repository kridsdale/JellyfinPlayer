//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Combine
import Defaults
import Foundation
import SwiftfinStorage

@MainActor
public final class StoredValueObservation<Value: Storable>: ObservableObject {
    private let key: StoredValues.Key<Value>
    private var task: Task<Void, Never>?
    private var observation: StoredDataObservation?
    public var value: Value {
        get { StoredValues[key] }
        set { objectWillChange.send()
            StoredValues[key] = newValue
        }
    }

    public init(_ key: StoredValues.Key<Value>) {
        self.key = key
        guard !key.name.isEmpty,!key.ownerID.isEmpty else { return }
        switch key.storage {
        case .defaults:
            task = Task { [weak self, key] in
                for await _ in Defaults.updates(key.defaultKey) {
                    guard let self else { return }
                    self.objectWillChange.send()
                }
            }
        case .sql:
            guard let data = try? JSONEncoder().encode(key.defaultValue()) else { return }
            observation = try? key.database.observe(key.address, defaultData: data) { [weak self] in
                self?.objectWillChange.send()
            }
        }
    }

    deinit { task?.cancel() }
}
