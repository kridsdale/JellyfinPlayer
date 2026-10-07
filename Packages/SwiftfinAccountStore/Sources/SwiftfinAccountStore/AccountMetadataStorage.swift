//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Defaults
import JellyfinAPI
import SwiftfinStoredValues

// Installed SDK metadata representation remains exactly Codable + Defaults.
// These conformances belong to the account metadata store, not the application.
extension PublicSystemInfo: @retroactive Defaults.Serializable, @retroactive Storable {}
extension UserDto: @retroactive Defaults.Serializable, @retroactive Storable {}
