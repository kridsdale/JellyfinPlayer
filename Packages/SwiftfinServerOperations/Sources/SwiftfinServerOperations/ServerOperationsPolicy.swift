//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation
import JellyfinAPI
import SwiftfinCollections

public enum ServerSessionFilter: String, Sendable { case all, active, inactive }
public enum ServerOperationsPolicy {
    public static func sortedKeys(_ values: [AuthenticationInfo]) -> [AuthenticationInfo] {
        values.sorted { ($0.appName ?? "").localizedCaseInsensitiveCompare($1.appName ?? "") == .orderedAscending }
    }

    public static func sortedDevices(_ values: [DeviceInfoDto])
    -> [DeviceInfoDto] {
        Array(values.sorted(using: \.dateLastActivity).reversed())
    }

    /// Captured time makes missing-date ordering stable within a snapshot.
    public static func sessionPrecedes(_ lhs: SessionInfoDto, _ rhs: SessionInfoDto, now: Date) -> Bool {
        let a = lhs.nowPlayingItem != nil
        let b = rhs.nowPlayingItem != nil
        if a != b {
            return a
        }
        if lhs.userName != rhs.userName {
            return (lhs.userName ?? "") < (rhs.userName ?? "")
        }
        if a {
            return (lhs.nowPlayingItem?.name ?? "") < (rhs.nowPlayingItem?.name ?? "")
        }
        return (lhs.lastActivityDate ?? now) > (rhs.lastActivityDate ?? now)
    }

    public static func sessions(
        _ values: [SessionInfoDto],
        activeWithinSeconds: Int?,
        filter: ServerSessionFilter,
        now: Date
    ) -> [SessionInfoDto] {
        values.filter { value in
            if let seconds = activeWithinSeconds, let date = value.lastActivityDate,
               now.timeIntervalSince(date) > TimeInterval(seconds)
            {
                return false
            }
            switch filter { case .all: return true
            case .active: return value.nowPlayingItem != nil
            case .inactive: return value.nowPlayingItem == nil }
        }.sorted { sessionPrecedes($0, $1, now: now) }
    }

    /// Preserve stream order: prefer this device's matching item, otherwise its
    /// first session. A missing device ID matches only another missing ID.
    public static func playbackSession(
        in values: [SessionInfoDto],
        deviceID: String?,
        itemID: String
    ) -> SessionInfoDto? {
        let deviceSessions = values.filter { $0.deviceID == deviceID }
        return deviceSessions.first(where: { $0.nowPlayingItem?.id == itemID }) ?? deviceSessions.first
    }

    public static func removedTaskIDs(
        existing: [String],
        incoming: [TaskInfo]
    ) -> Set<String> {
        Set(existing).subtracting(incoming.compactMap(\.id))
    }

    public static func triggers(
        removing trigger: TaskTriggerInfo,
        from values: [TaskTriggerInfo]
    ) -> [TaskTriggerInfo] {
        values.filter { $0 != trigger }
    }
}
