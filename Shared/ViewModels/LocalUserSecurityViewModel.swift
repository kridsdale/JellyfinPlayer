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

    private let securityUser: UserState?
    private let update: LocalSecurityUpdate?

    override init() {
        let manager = Container.shared.userSessionManager()
        let session = manager.currentSession
        self.securityUser = session?.user
        if let session {
            let client = session.client
            self.update = try? Container.shared.localAccountStore().securityUpdate(userID: session.user.id) {
                guard manager.currentSession === session, session.client === client else { throw CancellationError() }
            }
        } else {
            self.update = nil
        }
        super.init()
    }

    private func requireUpdate() throws -> LocalSecurityUpdate {
        guard let update else { throw UserSessionError.missingCurrentSession }
        try update.checkBinding()
        return update
    }

    func userForSecurityChange() throws -> UserState {
        _ = try requireUpdate()
        guard let securityUser else { throw UserSessionError.missingCurrentSession }
        return securityUser
    }

    func checkBinding() throws {
        _ = try requireUpdate()
    }

    func check(oldPin: String) throws {
        let update = try requireUpdate()
        guard try update.check(oldPIN: oldPin) else {
            throw ErrorMessage(L10n.incorrectPinForUser(securityUser?.username ?? ""))
        }
    }

    func set(newPolicy: LocalUserAccessPolicy, newPin: String, newPinHint: String) throws {
        do {
            try requireUpdate().commit(policy: newPolicy, pin: newPin, hint: newPinHint)
        } catch AccountStoreError.incorrectPIN {
            throw ErrorMessage(L10n.incorrectPinForUser(securityUser?.username ?? ""))
        }
    }
}
