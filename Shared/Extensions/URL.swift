//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation
import SwiftfinAccountModels
import SwiftfinText

extension URL {

    static let swiftfinGithub: URL = URL(string: "https://github.com/jellyfin/Swiftfin")!

    static let swiftfinGithubLicense: URL = URL(string: "https://github.com/jellyfin/Swiftfin/blob/main/LICENSE.md")!

    static let swiftfinGithubIssues: URL = URL(string: "https://github.com/jellyfin/Swiftfin/issues")!

    static let jellyfinDocsBackup: URL = URL(string: "https://jellyfin.org/docs/general/administration/backup-and-restore/")!

    static let jellyfinDocsDevices: URL = URL(string: "https://jellyfin.org/docs/general/server/devices")!

    static let jellyfinDocsTasks: URL = URL(string: "https://jellyfin.org/docs/general/server/tasks")!

    static let jellyfinDocsUsers: URL = URL(string: "https://jellyfin.org/docs/general/server/users")!

    static let jellyfinDocsTroubleshooting: URL = URL(string: "https://jellyfin.org/docs/general/administration/troubleshooting")!

    static let jellyfinDocsManagingUsers: URL = URL(string: "https://jellyfin.org/docs/general/server/users/adding-managing-users")!

    var normalizedServerConnectionURL: URL? {
        ServerConnection.normalizedURL(self)
    }
}
