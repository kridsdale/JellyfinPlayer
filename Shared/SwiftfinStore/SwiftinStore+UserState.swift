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
import SwiftfinAccountModels
import SwiftfinAccountStore
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

    /// Must pass the server to create a JellyfinClient
    /// with an access token
    @MainActor
    func getUserData(server: ServerState) async throws -> UserDto {
        let client = JellyfinClient(
            configuration: .swiftfinConfiguration(url: server.effectiveServerURL, accessToken: accessToken),
            sessionConfiguration: .swiftfin,
            sessionDelegate: URLSessionProxyDelegate(logger: NetworkLogger.swiftfin())
        )

        let request = Paths.getCurrentUser
        let response = try await client.send(request)

        return response.value
    }

    @MainActor
    func updateUserData(server: ServerState) async throws {
        let users = StoredValues[.User.users]
        guard let currentUser = users.first(where: { $0.id == id }) else { return }

        let userData = try await getUserData(server: server)
        let updatedUsername = userData.name ?? currentUser.username

        let updatedUser = UserState(
            id: currentUser.id,
            serverID: currentUser.serverID,
            username: updatedUsername
        )

        StoredValues[.User.users] = users.map { $0.id == id ? updatedUser : $0 }
        StoredValues[.User.data(id: currentUser.id)] = userData
    }

    func profileImageSource(
        client: JellyfinClient
    ) -> ImageSource {
        ImageSource(
            url: client.url(
                with: Paths.getUserImage(
                    parameters: Paths.GetUserImageParameters(
                        userID: id,
                        tag: data.primaryImageTag
                    )
                )
            )
        )
    }
}
