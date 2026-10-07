//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation
import JellyfinAPI
import SwiftfinAccountAccess
import SwiftfinImages
import SwiftfinLocalization
import SwiftfinNetworking

extension UserDto {

    @MainActor
    func profileImageSource(
        client: JellyfinTransport,
        maxWidth: CGFloat? = nil
    ) -> ImageSource {
        ImageSource(url: try? AccountAccessClient(transport: client).profileURL(userID: id ?? "", imageTag: primaryImageTag))
    }

    func getFullUser(userSession: UserSession) async throws -> UserDto {
        guard let id else {
            throw ErrorMessage(L10n.unknownError)
        }

        return try await userSession.userAdministration.user(id: id)
    }
}
