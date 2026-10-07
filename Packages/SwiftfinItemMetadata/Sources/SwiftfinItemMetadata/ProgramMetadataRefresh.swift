//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation
import JellyfinAPI

public enum ProgramMetadataRefreshError: Error, Sendable {
    case invalidDeadline
}

public enum ProgramMetadataRefresh {
    /// Refresh one second after the current program ends, with a one-second
    /// minimum wait for already-expired schedules. Time is captured once.
    public static func delay(after endDate: Date, comparedTo now: Date) throws -> Duration {
        let gap = endDate.timeIntervalSince(now)
        let seconds = max(gap + 1, 1)
        guard gap.isFinite, seconds.isFinite, seconds < Double(Int64.max) else {
            throw ProgramMetadataRefreshError.invalidDeadline
        }
        return .seconds(seconds)
    }
}

public extension ItemMetadataClient {
    /// The same account/transport must be current before the wait and on both
    /// sides of the metadata read. The injected wait is used by native tests.
    func item(
        id: String,
        afterProgramEnd endDate: Date,
        comparedTo now: Date = .now,
        wait: @escaping @MainActor @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) async throws -> BaseItemDto {
        try checkBinding()
        let delay = try ProgramMetadataRefresh.delay(after: endDate, comparedTo: now)
        try await wait(delay)
        try checkBinding()
        let result = try await item(id: id)
        try checkBinding()
        return result
    }
}
