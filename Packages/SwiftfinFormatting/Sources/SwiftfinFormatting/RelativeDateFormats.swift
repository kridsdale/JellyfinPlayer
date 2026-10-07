//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation
import SwiftfinLocalization
import SwiftfinValues

public struct LastSeenFormatStyle: FormatStyle {

    public init() {}

    public func format(_ value: Date?) -> String {

        guard let value else {
            return L10n.never
        }

        let timeInterval = Date.now.timeIntervalSince(value)
        let twentyFourHours: TimeInterval = 24 * 60 * 60

        if timeInterval <= twentyFourHours {
            return value.formatted(.relative(presentation: .numeric, unitsStyle: .narrow))
        } else {
            return value.formatted(Date.FormatStyle.dateTime.year().month().day())
        }
    }
}

public extension FormatStyle where Self == LastSeenFormatStyle {

    static var lastSeen: LastSeenFormatStyle {
        LastSeenFormatStyle()
    }
}

public extension FormatStyle where Self == AgeFormatStyle {

    static var age: AgeFormatStyle {
        AgeFormatStyle()
    }
}

public struct AgeFormatStyle: FormatStyle {

    public init() {}

    private var death: Date?

    public func death(_ date: Date?) -> AgeFormatStyle {
        copy(self, modifying: \.death, to: date)
    }

    public func format(_ value: Date) -> String {
        let age = Calendar.current.dateComponents([.year], from: value, to: death ?? .now).year ?? 0
        return L10n.yearsOld(age)
    }
}
