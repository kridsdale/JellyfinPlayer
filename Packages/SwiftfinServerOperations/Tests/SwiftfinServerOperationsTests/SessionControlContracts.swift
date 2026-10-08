//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import JellyfinAPI
import SwiftfinServerOperations
import Testing

struct SessionControlContracts {
    @Test
    func `ownership additional users and administrator authority preserve playback controls`() {
        var session = SessionInfoDto(
            isSupportsMediaControl: true, nowPlayingItem: .init(id: "media"), userID: "owner"
        )
        for (userID, permission, expected) in [
            ("owner", false, true), ("other", false, false), ("other", true, true)
        ] {
            let controls = ServerOperationsPolicy.sessionControls(for: session, userID: userID, mayControlOtherUsers: permission)
            #expect(controls.canControl == expected && controls.canControlPlayback == expected)
        }
        session.additionalUsers = [.init(userID: "guest")]
        #expect(ServerOperationsPolicy.sessionControls(for: session, userID: "guest", mayControlOtherUsers: false).canControlPlayback)
        session.userID = nil
        #expect(ServerOperationsPolicy.sessionControls(for: session, userID: "other", mayControlOtherUsers: false).canControlPlayback)
        #expect(!ServerOperationsPolicy.sessionControls(for: session, userID: nil, mayControlOtherUsers: true).canControl)
    }

    @Test
    func `message capability stays independent while playback requires media support and an item`() {
        var session = SessionInfoDto(supportedCommands: [.displayMessage], userID: "other")
        let noOwner = ServerOperationsPolicy.sessionControls(for: session, userID: nil, mayControlOtherUsers: false)
        #expect(noOwner.canSendMessage && !noOwner.canControlPlayback)
        session.userID = "me"
        session.isSupportsMediaControl = true
        #expect(!ServerOperationsPolicy.sessionControls(for: session, userID: "me", mayControlOtherUsers: false).canControlPlayback)
        session.nowPlayingItem = .init(id: "media")
        #expect(ServerOperationsPolicy.sessionControls(for: session, userID: "me", mayControlOtherUsers: false).canControlPlayback)
        session.isSupportsMediaControl = nil
        session.supportedCommands = nil
        let unsupported = ServerOperationsPolicy.sessionControls(for: session, userID: "me", mayControlOtherUsers: false)
        #expect(unsupported.canControl && !unsupported.canControlPlayback && !unsupported.canSendMessage)
    }
}
