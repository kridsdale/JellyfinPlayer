//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation
import SwiftfinValues

@_exported import CasePaths
@_exported import Engine

// StatefulMacro erases closure executor annotations in its worker registry.
// Keep app @Function handlers async: the generated await crosses to the
// explicitly main-actor-isolated method before it touches UI or session state.
@_exported import StatefulMacros
@_exported import SwiftfinMacros
