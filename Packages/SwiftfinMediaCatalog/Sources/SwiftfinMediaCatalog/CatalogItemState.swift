//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation
import JellyfinAPI
import SwiftfinTime

/// One captured instant makes all availability and progress decisions consistent.
/// Construction is cheap; each projection computes only the requested value.
public struct CatalogItemState: Sendable {
    private let item: BaseItemDto
    private let now: Date
    public init(_ item: BaseItemDto, at now: Date) {
        self.item = item
        self.now = now
    }

    public var isLiveStream: Bool {
        item.channelType == .tv
    }

    public var isMissing: Bool {
        item.locationType == .virtual
    }

    public var isPlayable: Bool {
        !isMissing && item.type != .series
    }

    public var isAiring: Bool {
        if let current = item.currentProgram {
            return Self(current, at: now).isAiring
        }
        guard let start = item.startDate, let end = item.endDate else { return false }
        // Item availability includes the end instant; EPG blocks are half-open.
        return start <= now && now <= end
    }

    public var runtime: Duration? {
        guard let ticks = item.runTimeTicks, ticks > 0 else { return nil }
        return .ticks(ticks)
    }

    public var startSeconds: Duration? {
        item.userData?.playbackPositionTicks.map(Duration.ticks)
    }

    /// The installed poster label uses whole remaining seconds for resumed media,
    /// then elapsed airing time. This differs from spoken remaining duration.
    public var progressLabelInterval: TimeInterval? {
        if let current = item.currentProgram {
            return Self(current, at: now).progressLabelInterval
        }
        if let position = item.userData?.playbackPositionTicks,
           let total = item.runTimeTicks,
           position != 0, total != 0
        {
            let (remaining, overflow) = total.subtractingReportingOverflow(position)
            // Malformed server values cannot trap the presentation caller.
            guard !overflow else { return nil }
            return TimeInterval(remaining / 10_000_000)
        }
        guard isAiring, let start = item.startDate else { return nil }
        return now.timeIntervalSince(start)
    }

    /// Raw state and durations only; the app chooses localized spoken labels.
    public func playbackState(canBePlayed: Bool) -> CatalogPlaybackState {
        let isProgram = item.type == .program || item.type == .liveTvProgram || item.type == .tvProgram
        if isProgram || isLiveStream || item.type == .tvChannel || item.type == .liveTvChannel {
            if isAiring, let start = item.startDate, let end = item.endDate, end > start {
                return .init(phase: .live, remainingDuration: .seconds(max(0, end.timeIntervalSince(now))))
            }
            if isUnaired {
                return .init(phase: .unaired)
            }
            if hasAired {
                return .init(phase: .ended)
            }
            return .init(phase: isLiveStream ? .live : nil)
        }
        if isUnaired {
            return .init(phase: .unaired)
        }
        if isMissing {
            return .init(phase: .missing)
        }
        guard canBePlayed else { return .init() }

        let position = max(0, item.userData?.playbackPositionTicks ?? 0)
        let percentage = item.userData?.playedPercentage ?? 0
        let hasProgress = position > 0 || (item.userData?.isPlayed != true && percentage.isFinite && percentage > 0)
        let phase: CatalogPlaybackState.Phase?
        var remaining: Duration?
        if hasProgress {
            phase = item.userData?.isPlayed == true ? .rewatching : .inProgress
            if let runtime = item.runTimeTicks, runtime > 0, position > 0 {
                remaining = .ticks(max(0, runtime - position))
            }
        } else {
            phase = item.userData?.isPlayed.map { $0 ? .played : .unplayed }
        }
        let count = item.userData?.unplayedItemCount
        return .init(
            phase: phase,
            remainingDuration: remaining,
            unplayedCount: item.userData?.isPlayed != true && (count ?? 0) > 0 ? count : nil
        )
    }

    public var programDuration: TimeInterval? {
        guard let start = item.startDate, let end = item.endDate else { return nil }
        return end.timeIntervalSince(start)
    }

    public var programProgress: Double? {
        programProgress(relativeTo: now)
    }

    public func programProgress(relativeTo instant: Date) -> Double? {
        guard let start = item.startDate, let end = item.endDate else { return nil }
        // Retain the original raw ratio, including nonfinite invalid-span results.
        return instant.timeIntervalSince(start) / end.timeIntervalSince(start)
    }

    public var progressPercentage: Double? {
        if let current = item.currentProgram {
            return Self(current, at: now).progressPercentage
        }
        if isAiring, let start = item.startDate, let end = item.endDate {
            let length = end.timeIntervalSince(start)
            guard length > 0 else { return nil }
            return min(max(now.timeIntervalSince(start) / length, 0), 1)
        }
        guard let percentage = item.userData?.playedPercentage, percentage > 0 else { return nil }
        return percentage / 100
    }

    public var isRecording: Bool {
        if let current = item.currentProgram {
            return Self(current, at: now).isRecording
        }
        return item.timerID != nil
    }

    public var isUnaired: Bool {
        if let start = item.startDate {
            return start > now
        }
        if let premiere = item.premiereDate {
            return premiere > now
        }
        return false
    }

    public var hasAired: Bool {
        guard let start = item.startDate, let end = item.endDate else { return false }
        return start <= now && end < now
    }

    public func presentsPlayButton(permitted: Bool) -> Bool {
        guard permitted else { return false }
        switch item.type {
        case .audio, .audioBook, .book, .channel, .channelFolderItem, .episode,
             .movie, .liveTvChannel, .liveTvProgram, .musicAlbum, .musicArtist, .musicVideo, .playlist,
             .program, .recording, .season, .series, .trailer, .tvChannel, .tvProgram, .video: return true
        default: return false
        }
    }

    public var parentTitle: String? {
        switch item.type {
        case .audio: item.album
        case .episode, .season: item.seriesName
        case .musicAlbum: item.albumArtist
        case .liveTvProgram, .program, .tvProgram: item.channelName
        default: nil
        }
    }

    public var parentRootID: String? {
        item.type == .episode ? item.seriesID : item.parentID
    }
}
