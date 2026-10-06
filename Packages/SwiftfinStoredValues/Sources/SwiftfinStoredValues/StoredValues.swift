//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Defaults
import Foundation
import SwiftfinStorage

@MainActor
public enum StoredValues {

    public typealias Keys = _AnyKey

    // swiftformat:disable enumnamespaces
    public class _AnyKey {
        public typealias Key = StoredValues.Key
    }

    /// A key to an `AnyData` object.
    ///
    /// - Important: if `name` or `ownerID` are empty, the default value
    ///              will always be retrieved and nothing will be set.
    @MainActor
    public final class Key<Value: Storable>: _AnyKey {

        public enum StorageDestination: Sendable {
            case defaults
            case sql
        }

        public let defaultValue: () -> Value
        public let field: String?
        public let name: String
        public let ownerID: String
        public let storage: StorageDestination

        let database: SwiftfinDatabase
        var address: StoredDataAddress {
            StoredDataAddress(ownerID: ownerID, field: field ?? name, key: name)
        }

        var defaultKey: Defaults.Key<Value> {

            let resolvedName: String = if field == name || field == nil {
                name
            } else {
                "\(field!)-\(name)"
            }

            return Defaults.Key(
                resolvedName,
                suite: UserDefaults(suiteName: ownerID)!,
                default: defaultValue
            )
        }

        public init(
            _ name: String,
            ownerID: String,
            field: String?,
            storage: StorageDestination = .sql,
            default defaultValue: @autoclosure @escaping () -> Value,
            database: SwiftfinDatabase = .shared
        ) {
            self.database = database
            self.defaultValue = defaultValue
            self.field = field
            self.name = name
            self.ownerID = ownerID

            // tvOS only supports user defaults storage
            #if os(tvOS)
            self.storage = .defaults
            #else
            self.storage = storage
            #endif
        }

        /// Always returns the given value and does not
        /// set anything to storage.
        public init(always: @autoclosure @escaping () -> Value) {
            database = .shared
            defaultValue = always
            field = nil
            name = "always"
            ownerID = ""
            storage = .defaults
        }
    }

    public static subscript<Value: Storable>(key: Key<Value>) -> Value {
        get {
            guard !key.name.isEmpty, !key.ownerID.isEmpty else { return key.defaultValue() }

            switch key.storage {
            case .defaults:
                return Defaults[key.defaultKey]
            case .sql:
                guard let data = try? key.database.read(key.address),
                      let value = try? JSONDecoder().decode(Value.self, from: data) else { return key.defaultValue() }
                return value
            }
        }
        set {
            guard !key.name.isEmpty, !key.ownerID.isEmpty else { return }

            switch key.storage {
            case .defaults:
                Defaults[key.defaultKey] = newValue
            case .sql:
                if let data = try? JSONEncoder().encode(newValue) {
                    try? key.database.write(data, at: key.address)
                }
            }
        }
    }
}
