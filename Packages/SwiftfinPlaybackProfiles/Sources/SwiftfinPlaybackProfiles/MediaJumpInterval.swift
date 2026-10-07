//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation

public enum MediaJumpInterval: CaseIterable, Hashable, RawRepresentable, Codable, Sendable {

    public typealias RawValue = Duration

    case five
    case ten
    case fifteen
    case thirty
    case custom(interval: Duration)

    public init(rawValue: Duration) {
        switch rawValue {
        case .seconds(5):
            self = .five
        case .seconds(10):
            self = .ten
        case .seconds(15):
            self = .fifteen
        case .seconds(30):
            self = .thirty
        default:
            self = .custom(interval: rawValue)
        }
    }

    public var rawValue: Duration {
        switch self {
        case .five:
            .seconds(5)
        case .ten:
            .seconds(10)
        case .fifteen:
            .seconds(15)
        case .thirty:
            .seconds(30)
        case let .custom(interval):
            interval
        }
    }

    public static var allCases: [MediaJumpInterval] {
        [.five, .ten, .fifteen, .thirty]
    }
}
