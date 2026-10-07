//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import SwiftfinLocalization
import SwiftfinServerOperations

typealias ServerLogType = ServerLogKind

extension ServerLogKind: Displayable, SystemImageable {
    var displayTitle: String {
        switch self {
        case .directStream:
            L10n.directStream
        case .remux:
            L10n.remux
        case .transcode:
            L10n.transcode
        case .system:
            L10n.system
        case .other:
            L10n.other
        }
    }

    var systemImage: String {
        switch self {
        case .directStream:
            "arrow.forward"
        case .remux:
            "arrow.left.arrow.right"
        case .transcode:
            "shuffle"
        case .system:
            "gearshape.fill"
        case .other:
            "staroflife.fill"
        }
    }
}
