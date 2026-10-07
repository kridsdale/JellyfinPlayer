//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import FactoryKit
import Foundation
import SwiftfinAccountModels
import SwiftfinAccountStore
import SwiftfinLocalization

final class LocalUserSecurityViewModel: ViewModel {

    func check(oldPin: String) throws {
        let user = try authenticatedUser

        guard try Container.shared.localAccountStore().matchesPIN(oldPin, userID: user.id, allowMissing: true) else {
            throw ErrorMessage(L10n.incorrectPinForUser(user.username))
        }
    }

    func set(newPolicy: LocalUserAccessPolicy, newPin: String, newPinHint: String) throws {
        let user = try authenticatedUser

        try Container.shared.localAccountStore().setLocalSecurity(
            userID: user.id,
            policy: newPolicy,
            pin: newPin,
            hint: newPinHint
        )
    }
}
