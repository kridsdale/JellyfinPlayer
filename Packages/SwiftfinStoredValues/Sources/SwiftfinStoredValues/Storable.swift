//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Defaults
import SwiftfinAccountModels

public protocol Storable: Codable, Defaults.Serializable {}
extension Array: Storable where Element: Storable {}
extension Bool: Storable {}
extension Int: Storable {}
extension String: Storable {}

extension ServerAccountRecord: @retroactive Defaults.Serializable, Storable {}
extension UserAccountRecord: @retroactive Defaults.Serializable, Storable {}

extension LocalUserAccessPolicy: @retroactive Defaults.Serializable, Storable {}
extension ServerConnection: @retroactive Defaults.Serializable, Storable {}
extension ServerConnection.Interface: @retroactive Defaults.Serializable, Storable {}
extension UserSessionState: @retroactive Defaults.Serializable, Storable {}

extension ServerSelection: @retroactive Defaults.Serializable, Storable {}
