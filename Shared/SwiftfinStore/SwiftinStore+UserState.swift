//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import FactoryKit
import Foundation
import JellyfinAPI
import Pulse
import SwiftfinAccountAccess
import SwiftfinAccountModels
import SwiftfinAccountStore
import SwiftfinImages
import SwiftfinNetworking
import SwiftfinStoredValues
import UIKit

@MainActor
extension UserState {

    typealias Key = StoredValues.Key

    var accessToken: String {
        guard let token = try? Container.shared.localAccountStore().accessToken(userID: id) else {
            assertionFailure("access token missing in keychain")
            return ""
        }
        return token
    }

    func storeAccessToken(_ token: String) throws {
        try Container.shared.localAccountStore().storeAccessToken(token, userID: id)
    }

    var data: UserDto {
        get {
            StoredValues[.User.data(id: id)]
        }
        nonmutating set {
            StoredValues[.User.data(id: id)] = newValue
        }
    }

    var pin: String {
        guard let pin = try? Container.shared.localAccountStore().pin(userID: id) else {
            assertionFailure("pin missing in keychain")
            return ""
        }
        return pin
    }

    func storePIN(_ pin: String) throws {
        try Container.shared.localAccountStore().storePIN(pin, userID: id)
    }

    var pinHint: String {
        get { Container.shared.localAccountStore().pinHint(userID: id) }
        nonmutating set { Container.shared.localAccountStore().setPINHint(newValue, userID: id) }
    }

    var accessPolicy: LocalUserAccessPolicy {
        get { Container.shared.localAccountStore().accessPolicy(userID: id) }
        nonmutating set { Container.shared.localAccountStore().setAccessPolicy(newValue, userID: id) }
    }
}

@MainActor
extension UserState {

    /// Deletes the model that this state represents and
    /// all settings from `Defaults` `Keychain`, and `StoredValues`
    func delete() throws {
        try Container.shared.localAccountStore().deleteUser(self)
    }

    /// Deletes user settings from `UserDefaults` and `StoredValues`
    func deleteSettings() throws {
        try Container.shared.localAccountStore().deleteSettings(userID: id)
    }

    /// Must pass the server to create a JellyfinTransport
    /// with an access token
    @MainActor
    func getUserData(server: ServerState) async throws -> UserDto {
        try await accountAccess(server: server).currentUser(expectedUserID: id)
    }

    private func accountAccess(server: ServerState) -> AccountAccessClient {
        let url = server.effectiveServerURL
        let token = accessToken
        let client = JellyfinTransport.swiftfin(url: url, accessToken: token)
        let store = Container.shared.localAccountStore()
        return AccountAccessClient(transport: client, expectedServerID: server.id, isCurrent: {
            server.effectiveServerURL == url && (try? store.accessToken(userID: id)) == token
        })
    }

    @MainActor
    func updateUserData(server: ServerState, validate: @MainActor @Sendable () throws -> Void = {}) async throws {
        try validate()
        let access = accountAccess(server: server)
        let userData = try await access.currentUser(expectedUserID: id)
        try access.checkBinding()
        try validate()
        try Container.shared.localAccountStore().updateUserMetadata(userID: id, serverID: server.id, data: userData)
    }

    func profileImageSource(
        client: JellyfinTransport
    ) -> ImageSource {
        ImageSource(url: try? AccountAccessClient(transport: client).profileURL(userID: id, imageTag: data.primaryImageTag))
    }
}
