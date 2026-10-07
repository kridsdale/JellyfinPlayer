//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Defaults
import Foundation
import SwiftfinAccountModels
import SwiftfinStoredValues
import Testing

@Suite(.serialized) @MainActor
struct ServerSelectionStorageContracts {
    @Test
    func `captured installed defaults strings remain readable and write identical bytes`() throws {
        let owner = "server-selection-test-" + UUID().uuidString
        let suite = try #require(UserDefaults(suiteName: owner))
        defer { suite.removePersistentDomain(forName: owner) }
        let defaults = Defaults.Key<ServerSelection>("selection", default: .all, suite: suite)
        let stored = StoredValues.Key("selection", ownerID: owner, field: nil, storage: .defaults, default: ServerSelection.all)
        let samples: [(ServerSelection, String)] = [
            (.all, "\"swiftfin-all\""),
            (.server(id: "swiftfin-all"), "\"swiftfin-all\""),
            (.server(id: ""), "\"\""),
            (.server(id: "A"), "\"A\""),
            (.server(id: "a"), "\"a\""),
            (.server(id: " A "), "\" A \""),
            (.server(id: "家🧒"), "\"家🧒\""),
            (.server(id: "missing"), "\"missing\"")
        ]
        for (selection, bytes) in samples {
            suite.set(bytes, forKey: "selection")
            let decoded = try JSONDecoder().decode(ServerSelection.self, from: Data(bytes.utf8))
            #expect(Defaults[defaults] == decoded)
            #expect(StoredValues[stored] == decoded)
            Defaults[defaults] = selection
            #expect(suite.string(forKey: "selection") == bytes)
            StoredValues[stored] = selection
            #expect(suite.string(forKey: "selection") == bytes)
        }
    }

    @Test
    func `two original app selection keys retain independent values`() throws {
        let owner = "server-selection-test-" + UUID().uuidString
        let suite = try #require(UserDefaults(suiteName: owner))
        defer { suite.removePersistentDomain(forName: owner) }
        let selection = Defaults.Key<ServerSelection>("selectUserServerSelection", default: .all, suite: suite)
        let splash = Defaults.Key<ServerSelection>("selectUserAllServersSplashscreen", default: .all, suite: suite)
        suite.set("\"A\"", forKey: "selectUserServerSelection")
        suite.set("\"swiftfin-all\"", forKey: "selectUserAllServersSplashscreen")
        #expect(Defaults[selection] == .server(id: "A") && Defaults[splash] == .all)
        Defaults[splash] = .server(id: "家🧒")
        #expect(Defaults[selection] == .server(id: "A"))
        #expect(suite.string(forKey: "selectUserAllServersSplashscreen") == "\"家🧒\"")
    }
}
