//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Defaults
import JellyfinAPI
import SwiftfinMediaTracks
import SwiftfinPlaybackPreparation
import SwiftfinPlaybackPreviews
import SwiftfinPlaybackProfiles
import SwiftfinPlaybackReporting
import SwiftfinText
import SwiftUI

// TODO: get preview image for current manager seconds?
//       - would make scrubbing image possibly ready before scrubbing
// TODO: fix leaks
//       - made from publishers of observers not being cancelled

@MainActor
class MediaPlayerItem: ViewModel, MediaPlayerObserver {

    typealias ThumbnailProvider = () async -> UIImage?

    @Published
    var selectedAudioStreamIndex: Int? = nil {
        didSet {
            guard let selectedAudioStreamIndex, selectedAudioStreamIndex != oldValue else { return }
            manager?.setTrack(type: .audio, from: oldValue, to: selectedAudioStreamIndex)
        }
    }

    @Published
    var selectedSubtitleStreamIndex: Int? = nil {
        didSet {
            guard selectedSubtitleStreamIndex != oldValue else { return }
            manager?.setTrack(type: .subtitle, from: oldValue, to: selectedSubtitleStreamIndex)
        }
    }

    private(set) var indexMap: MediaTrackIndexMap

    weak var manager: MediaPlayerManager? {
        didSet {
            for var o in observers {
                o.manager = manager
            }
        }
    }

    var observers: [any MediaPlayerObserver] = []

    let videoPlayerType: VideoPlayerType
    let connection: PlaybackConnection?
    let baseItem: BaseItemDto
    let deviceProfile: DeviceProfile
    let mediaSource: MediaSourceInfo
    let playSessionID: String
    let previewImageProvider: (any PreviewImageProvider)?
    let thumbnailProvider: ThumbnailProvider?
    let url: URL

    let audioStreams: [MediaStream]
    let subtitleStreams: [MediaStream]
    let sidecarSubtitles: [PreparedSidecarSubtitle]
    let videoStreams: [MediaStream]

    let requestedBitrate: PlaybackBitrate
    private let trackPolicy: MediaTrackPolicy

    // MARK: init

    init(
        connection: PlaybackConnection? = nil,
        videoPlayerType: VideoPlayerType = Defaults[.VideoPlayer.videoPlayerType],
        baseItem: BaseItemDto,
        mediaSource: MediaSourceInfo,
        playSessionID: String,
        url: URL,
        requestedBitrate: PlaybackBitrate = .max,
        deviceProfile: DeviceProfile,
        sidecarSubtitles: [PreparedSidecarSubtitle],
        compatibilityMode: PlaybackCompatibility = Defaults[.VideoPlayer.Playback.compatibilityMode],
        initialAudioStreamIndex: Int? = nil,
        initialSubtitleStreamIndex: Int? = nil,
        previewImageProvider: (any PreviewImageProvider)? = nil,
        thumbnailProvider: ThumbnailProvider? = nil
    ) {
        self.videoPlayerType = videoPlayerType
        self.connection = connection
        self.baseItem = baseItem
        self.mediaSource = mediaSource
        self.playSessionID = playSessionID
        self.requestedBitrate = requestedBitrate
        self.deviceProfile = deviceProfile
        self.sidecarSubtitles = sidecarSubtitles
        self.previewImageProvider = previewImageProvider
        self.thumbnailProvider = thumbnailProvider
        self.url = url

        let trackPolicy = MediaTrackPolicy(
            mediaSource: mediaSource,
            deviceProfile: deviceProfile,
            compatibility: compatibilityMode,
            audioIndex: initialAudioStreamIndex,
            subtitleIndex: initialSubtitleStreamIndex
        )
        self.trackPolicy = trackPolicy
        self.audioStreams = trackPolicy.audioStreams
        self.subtitleStreams = trackPolicy.subtitleStreams
        self.videoStreams = trackPolicy.videoStreams
        self.indexMap = trackPolicy.initialIndexMap

        super.init()

        selectedAudioStreamIndex = trackPolicy.selectedAudioIndex

        selectedSubtitleStreamIndex = trackPolicy.selectedSubtitleIndex

        if let id = baseItem.id, let connection {
            #if os(tvOS)
            let reportClient = connection.reportingClient(identity: .init(
                itemID: id, mediaSourceID: mediaSource.id, liveStreamID: mediaSource.liveStreamID,
                playSessionID: playSessionID, canSeek: !baseItem.isLiveStream,
                playMethod: mediaSource.transcodingURL == nil ? .directPlay : .transcode
            ))
            observers.append(KidsMediaProgressObserver(item: self, reportClient: reportClient))
            #else
            let reportClient = connection.reportingClient(identity: .init(
                itemID: id, mediaSourceID: mediaSource.id, liveStreamID: mediaSource.liveStreamID,
                playSessionID: playSessionID, sessionID: playSessionID
            ))
            observers.append(MediaProgressObserver(item: self, reportClient: reportClient))
            #endif
        }
    }

    /// Decides whether a track change can be performed by the player in place, or whether the server must produce a new stream.
    func isRebuildRequired(type: MediaStreamType, from oldIndex: Int?, to newIndex: Int?) -> Bool {
        trackPolicy.requiresRebuild(type: type, from: oldIndex, to: newIndex)
    }

    /// Switches audio or subtitles without rebuilding the stream.
    func switchTrack(type: MediaStreamType, index: Int?) {
        let playerIndex = indexMap.playerIndex(for: index)

        switch type {
        case .audio:
            guard let playerIndex,
                  let proxy = manager?.proxy as? any MediaPlayerAudioTrackConfigurable
            else { return }
            proxy.setAudioStream(.init(index: playerIndex))
        case .subtitle:
            guard let proxy = manager?.proxy as? any MediaPlayerSubtitleTrackConfigurable else { return }
            // Disable subtitles until the requested track is available.
            proxy.setSubtitleStream(.init(index: playerIndex ?? -1))
        default:
            return
        }
    }

    /// Replaces estimated track indexes with those reported by the player.
    func setTrackIndexes(_ indexMap: MediaTrackIndexMap) {
        self.indexMap = indexMap
        switchTrack(type: .audio, index: selectedAudioStreamIndex)
        switchTrack(type: .subtitle, index: selectedSubtitleStreamIndex)
    }

    /// Refreshes sidecar mappings and reapplies the selected subtitle.
    func updateSubtitleTrackMapping(subtitleTracks: [(playerIndex: Int, id: String)]) {
        let sidecars: [(jellyfinIndex: Int, url: URL)] = sidecarSubtitles.compactMap { subtitle in
            guard let jellyfinIndex = subtitle.jellyfinIndex else { return nil }
            return (jellyfinIndex, subtitle.url)
        }

        indexMap = indexMap.resolvingSidecarSubtitles(sidecars, subtitleTracks: subtitleTracks)
        switchTrack(type: .subtitle, index: selectedSubtitleStreamIndex)
    }
}
