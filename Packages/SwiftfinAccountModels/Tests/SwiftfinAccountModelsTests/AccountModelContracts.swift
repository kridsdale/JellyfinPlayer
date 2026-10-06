//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation
@testable import SwiftfinAccountModels
import Testing

private enum LegacySessionState: RawRepresentable, Codable {
    case signedOut
    case signedIn(userID: String)
    var rawValue: String {
        switch self { case .signedOut: ""
        case let .signedIn(id): id }
    }

    init?(rawValue: String) {
        self = rawValue.isEmpty ? .signedOut : .signedIn(userID: rawValue)
    }
}

struct AccountModelContracts {
    @Test
    func `legacy records retain their codable shape`() throws {
        let json = Data(
            #"{"id":"server","name":"Home","urls":["http://192.0.2.1:8096"],"currentURL":"http://192.0.2.1:8096","userIDs":["kid"]}"#
                .utf8
        )
        let server = try JSONDecoder().decode(ServerAccountRecord.self, from: json)
        #expect(server.userIDs == ["kid"])
        let object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(server)) as? NSDictionary
        #expect(try object == (JSONSerialization.jsonObject(with: json) as? NSDictionary))
        let user = try JSONDecoder().decode(UserAccountRecord.self, from: Data(#"{"id":"kid","serverID":"server","username":"Kid"}"#.utf8))
        #expect(user.username == "Kid")
    }

    @Test
    func `session raw and JSON encoding remain compatible`() throws {
        for value in ["", "kid-id"] {
            let old = try #require(LegacySessionState(rawValue: value))
            let new = try #require(UserSessionState(rawValue: value))
            #expect(new.rawValue == old.rawValue)
            let oldObject = try JSONSerialization.jsonObject(with: JSONEncoder().encode(old), options: .fragmentsAllowed)
            let newObject = try JSONSerialization.jsonObject(with: JSONEncoder().encode(new), options: .fragmentsAllowed)
            let oldJSON = try #require(oldObject as? NSObject)
            let newJSON = try #require(newObject as? NSObject)
            #expect(oldJSON.isEqual(newJSON))
            #expect(try JSONDecoder().decode(UserSessionState.self, from: JSONEncoder().encode(old)) == new)
        }
    }

    @Test
    func `connection interface and SSID rules are preserved`() throws {
        let wifi = try ServerConnection(
            id: "wifi",
            name: "Wi-Fi",
            url: #require(URL(string: "http://192.0.2.1")),
            interface: .wifi,
            wifiSSIDs: ["Home"],
            priority: 0
        )
        #expect(wifi.matches(.init(isSatisfied: true, interface: .wifi, wifiSSID: "home")))
        #expect(!wifi.matches(.init(isSatisfied: true, interface: .wifi, wifiSSID: "Away")))
        #expect(!wifi.matches(.init(isSatisfied: true, interface: .cellular, wifiSSID: nil)))
        #expect(NetworkConnectionContext(isSatisfied: true, interface: .wifi, wifiSSID: "  ").wifiSSID == nil)
    }

    @Test
    func `priority normalization and duplicate identity are preserved`() throws {
        let a = try ServerConnection(
            id: "A",
            name: "A",
            url: #require(URL(string: "http://192.0.2.1")),
            interface: .wifi,
            wifiSSIDs: ["Home", "Office"],
            priority: 5
        )
        let b = ServerConnection(id: "B", name: "B", url: a.url, interface: .wifi, wifiSSIDs: ["office", "home"], priority: 2)
        #expect(ServerConnection.isDuplicate(a, in: [b]))
        #expect(!ServerConnection.isDuplicate(a, in: [a]))
        #expect(ServerConnection.ordered([a, b]).map(\.id) == ["B", "A"])
        #expect(ServerConnection.ordered([a, b], preservingOrder: true).map(\.priority) == [0, 1])
        #expect(ServerConnection.ordered([a, b], preservingOrder: true).map(\.id) == ["A", "B"])
    }

    @Test
    func `legacy blank and trimmed display values remain exact`() throws {
        let url = try #require(URL(string: "http://192.0.2.1"))
        let named = ServerConnection(id: "A", name: "  Home \n", url: url, interface: .any, priority: 0)
        let blank = ServerConnection(id: "B", name: "  ", url: url, interface: .any, priority: 1)
        #expect(named.displayTitle == "Home")
        #expect(blank.displayTitle == url.absoluteString)
        #expect(NetworkConnectionContext(isSatisfied: true, interface: .wifi, wifiSSID: " Home ").wifiSSID == "Home")
    }

    @Test
    func `values transfer across executors without services or settings`() async {
        let user = UserAccountRecord(id: "kid", serverID: "server", username: "Kid")
        let captured = await Task.detached { (user.id, UserSessionState.signedIn(userID: user.id).rawValue) }.value
        #expect(captured.0 == "kid")
        #expect(captured.1 == "kid")
        #expect(LocalUserAccessPolicy.none.authenticateReason(user: user) == nil)
        #expect(LocalUserAccessPolicy.requirePin.createReason(user: user) != nil)
    }
}
