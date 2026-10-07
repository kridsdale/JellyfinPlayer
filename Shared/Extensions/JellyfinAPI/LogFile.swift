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
import SwiftfinServerOperations

extension LogFile {

    @MainActor
    var url: URL? {
        guard let client = Container.shared.currentUserSession()?.client else { return nil }
        return ServerDiagnosticURLPolicy.logURL(name: name, using: client)
    }

    var type: ServerLogType {
        ServerLogType(rawValue: name)
    }
}
