//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import JellyfinAPI

/// Immutable interpretation of incoming commands. Native players, preferences,
/// account binding and application navigation belong to the receiving host.
public enum RemotePlaybackIntent: Equatable, Sendable {
    case playItem(id: String, mediaSourceID: String?, startPositionTicks: Int?)
    case nextTrack
    case previousTrack
    case fastForward
    case rewind
    case pause
    case unpause
    case playPause
    case stop
    case seek(ticks: Int)
    case audioStream(index: Int)
    case subtitleStream(index: Int)
    case maxBitrate(Int)
    case displayItem(id: String)
    case trailers(itemID: String)
    case ignore
}

public enum RemotePlaybackCommandPolicy {
    public static func play(_ command: PlayRequest) -> RemotePlaybackIntent {
        switch command.playCommand {
        case .playNow, .none:
            let ids = command.itemIDs ?? []
            let index = command.startIndex ?? 0
            guard let id = ids.indices.contains(index) ? ids[index] : ids.first else { return .ignore }
            return .playItem(id: id, mediaSourceID: command.mediaSourceID, startPositionTicks: command.startPositionTicks)
        case .playNext: return .nextTrack
        case .playLast: return .previousTrack
        case .playInstantMix, .playShuffle: return .ignore
        }
    }

    public static func playstate(_ command: PlaystateRequest) -> RemotePlaybackIntent {
        switch command.command {
        case .fastForward: return .fastForward
        case .nextTrack: return .nextTrack
        case .pause: return .pause
        case .playPause: return .playPause
        case .previousTrack: return .previousTrack
        case .rewind: return .rewind
        case .seek:
            guard let ticks = command.seekPositionTicks else { return .ignore }
            return .seek(ticks: ticks)
        case .stop: return .stop
        case .unpause: return .unpause
        case .none: return .ignore
        }
    }

    public static func general(_ command: GeneralCommand) -> RemotePlaybackIntent {
        switch command.name {
        case .setAudioStreamIndex:
            guard let text = command.arguments?["Index"], let index = Int(text) else { return .ignore }
            return .audioStream(index: index)
        case .setMaxStreamingBitrate:
            guard let text = command.arguments?["Bitrate"], let bitrate = Int(text) else { return .ignore }
            return .maxBitrate(bitrate)
        case .setSubtitleStreamIndex:
            guard let text = command.arguments?["Index"], let index = Int(text) else { return .ignore }
            return .subtitleStream(index: index)
        case .displayContent:
            guard let id = command.arguments?["ItemId"] else { return .ignore }
            return .displayItem(id: id)
        case .playMediaSource:
            guard let id = command.arguments?["ItemId"] else { return .ignore }
            return .playItem(id: id, mediaSourceID: command.arguments?["MediaSourceId"], startPositionTicks: nil)
        case .playTrailers:
            guard let id = command.arguments?["ItemId"] else { return .ignore }
            return .trailers(itemID: id)
        default: return .ignore
        }
    }
}
