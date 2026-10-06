//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation
import SwiftfinStoredValues
import SwiftfinStoredValuesUI
import Testing

@MainActor
struct StoredValueBindingTests {
    @Test
    func `projected binding updates the exact owner key`() throws {
        let owner = "binding-test-" + UUID().uuidString
        let suite = try #require(UserDefaults(suiteName: owner))
        defer { suite.removePersistentDomain(forName: owner) }
        let key = StoredValues.Key("position", ownerID: owner, field: "episode", storage: .defaults, default: 1)
        let wrapper = StoredValue(key)
        wrapper.projectedValue.wrappedValue = 19
        #expect(StoredValues[key] == 19)
        #expect(wrapper.wrappedValue == 19)
        wrapper.wrappedValue = 33
        #expect(wrapper.projectedValue.wrappedValue == 33)
    }
}
