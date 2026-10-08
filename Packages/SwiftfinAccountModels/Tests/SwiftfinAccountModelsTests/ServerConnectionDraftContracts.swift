//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation
import SwiftfinAccountModels
import Testing

struct ServerConnectionDraftContracts {
    private func draft() throws -> ServerConnectionDraft {
        try ServerConnectionDraft(connection: .init(
            id: "connection", name: " Home ", url: #require(URL(string: "http://example.test")),
            interface: .wifi, wifiSSIDs: [" Home "], priority: 7
        ))
    }

    @Test
    func `URL editing preserves scheme host port base path query and fragment rules`() throws {
        for (input, expected) in [
            (" 192.0.2.7:8096/ \n", "http://192.0.2.7:8096"),
            ("HTTPS://Example.TEST/base/?tag=a%20b&x=1", "https://example.test/base?tag=a%20b&x=1"),
            ("http://Example.TEST:8096/a//?tag=synthetic#local", "http://example.test:8096/a/?tag=synthetic#local")
        ] {
            var value = try draft()
            value.urlString = input
            let connection = try value.connection()
            #expect(connection.url.absoluteString == expected)
            #expect(connection.id == "connection" && connection.name == "Home" && connection.priority == 7)
        }
    }

    @Test
    func `SSID editing trims removes blanks sorts and retains duplicate and case bytes`() throws {
        var value = try draft()
        value.wifiSSIDs = [" Office ", "\n", "Home", " home ", "Home"]
        #expect(try value.connection().wifiSSIDs == ["Home", "Home", "Office", "home"])
        value.useWifiName = false
        #expect(try value.connection().wifiSSIDs.isEmpty)
        value.useWifiName = true
        for interface in [ServerConnection.Interface.any, .cellular] {
            value.interface = interface
            #expect(try value.connection().wifiSSIDs.isEmpty)
        }
    }

    @Test
    func `invalid URL or selected blank WiFi name leaves the draft unchanged`() throws {
        var value = try draft()
        value.urlString = "http://[invalid"
        let invalidURL = value
        #expect(throws: ServerConnectionDraftError.invalidURL) { try value.connection() }
        #expect(value == invalidURL)
        value.urlString = "example.test"
        value.wifiSSIDs = [" ", "\n"]
        let invalidWiFi = value
        #expect(throws: ServerConnectionDraftError.invalidWifiName) { try value.connection() }
        #expect(value == invalidWiFi)
        value.useWifiName = false
        #expect(try value.connection().wifiSSIDs.isEmpty)
    }

    @Test
    func `draft value transfers without network or settings access and retains the original`() async throws {
        let original = try draft()
        let updated = await Task.detached {
            var value = original
            value.name = "Other"
            value.interface = .any
            return value
        }.value
        #expect(updated.name == "Other" && updated.interface == .any)
        #expect(original.name == " Home " && original.interface == .wifi)
        #expect(updated.id == original.id && updated.priority == original.priority)
    }
}
