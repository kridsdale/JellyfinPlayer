//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import SwiftfinAccountModels

typealias DeepLink = AccountDeepLink
typealias DeepLinkError = AccountDeepLinkError

extension AccountDeepLink {
    @MainActor
    func route() -> NavigationRoute {
        switch destination {
        case let .item(id):
            .item(id: id)
        }
    }
}
