//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Defaults
import SwiftfinStorage

public protocol Storable: Codable, Defaults.Serializable {}
extension Array: Storable where Element: Storable {}
extension Bool: Storable {}
extension Int: Storable {}
extension String: Storable {}

extension SwiftfinStore.State.Server: @retroactive Defaults.Serializable, Storable {}
extension SwiftfinStore.State.User: @retroactive Defaults.Serializable, Storable {}
