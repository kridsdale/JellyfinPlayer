//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Defaults
import FactoryKit
import Foundation
import JellyfinAPI
import Logging
import SwiftfinFormatting
import SwiftfinLocalization
import SwiftfinMediaTracks
import SwiftfinPlaybackPreparation
import SwiftfinPlaybackPreviews
import SwiftfinPlaybackProfiles
import SwiftfinStoredValues
import SwiftfinText
#if os(tvOS)
import KidsDiagnostics
#endif

// TODO: build report of determined values for playback information
//       - transcode, video stream, path

extension MediaPlayerItem {

    /// The main `MediaPlayerItem` builder for normal online usage.
    static func build(
        for initialItem: BaseItemDto,
        preparedItem: BaseItemDto? = nil,
        mediaSource _initialMediaSource: MediaSourceInfo? = nil,
        audioStreamIndex: Int? = nil,
        subtitleStreamIndex: Int? = nil,
        videoPlayerType: VideoPlayerType = Defaults[.VideoPlayer.videoPlayerType],
        requestedBitrate: PlaybackBitrate = Defaults[.VideoPlayer.Playback.appMaximumBitrate],
        compatibilityMode: PlaybackCompatibility = Defaults[.VideoPlayer.Playback.compatibilityMode],
        modifyItem: ((inout BaseItemDto) -> Void)? = nil
    ) async throws -> MediaPlayerItem {

        let logger = Logger.swiftfin()

        guard let itemID = initialItem.id else {
            logger.critical("No item ID!")
            throw ErrorMessage(L10n.unknownError)
        }

        guard let userSession = Container.shared.currentUserSession() else {
            logger.critical("No user session!")
            throw ErrorMessage(L10n.unknownError)
        }

        let transport = userSession.client
        let preparation = userSession.playbackPreparation
        try preparation.checkBinding()

        var item: BaseItemDto
        if let preparedItem {
            // The kids path fetched and validated this full DTO for this exact
            // start. Other callers retain their existing fresh-fetch behavior.
            item = preparedItem
        } else {
            #if os(tvOS)
            let metadataTrace = KidsPerformance.begin(.metadata, endpoint: .itemDetails)
            defer { metadataTrace?.finish(Task.isCancelled ? .cancelled : .failure) }
            item = try await preparation.item(
                id: itemID,
                delegate: metadataTrace.map(KidsPerformanceTaskDelegate.init(span:))
            )
            metadataTrace?.finish()
            #else
            item = try await preparation.item(id: itemID)
            #endif
        }
        guard item.id == itemID else { throw ErrorMessage("Playback item identity changed") }

        if let modifyItem {
            modifyItem(&item)
        }

        guard item.id == itemID else { throw ErrorMessage("Playback item identity changed") }
        let initialMediaSource: MediaSourceInfo
        do { initialMediaSource = try PlaybackPreparationPolicy.initialSource(in: item, preferred: _initialMediaSource) }
        catch { throw ErrorMessage(L10n.unknownError) }

        #if os(tvOS)
        let bitrateTrace = KidsPerformance.begin(.bitrate, endpoint: .bitrate, values: ["automatic": requestedBitrate == .auto ? 1 : 0])
        defer { bitrateTrace?.finish(Task.isCancelled ? .cancelled : .failure) }
        #endif
        let maxBitrate = try await MediaPlayerManager.getMaxBitrate(for: requestedBitrate, preparation: preparation)
        #if os(tvOS)
        bitrateTrace?.finish(values: ["bits_per_second": Double(maxBitrate)])
        #endif

        let deviceProfile = DeviceProfile.build(
            for: videoPlayerType,
            compatibilityMode: compatibilityMode,
            maxBitrate: maxBitrate
        )

        let resolved: PreparedPlayback
        #if os(tvOS)
        let infoTrace = KidsPerformance.begin(.playbackInfo, endpoint: .playbackInfo)
        defer { infoTrace?.finish(Task.isCancelled ? .cancelled : .failure) }
        do {
            resolved = try await preparation.prepare(
                item: item,
                initial: initialMediaSource,
                profile: deviceProfile,
                maxBitrate: maxBitrate,
                audio: audioStreamIndex,
                subtitle: subtitleStreamIndex,
                delegate: infoTrace.map(KidsPerformanceTaskDelegate.init(span:))
            )
        } catch is PlaybackPreparationError { throw ErrorMessage(L10n.unknownError) }
        infoTrace?.finish()
        #else
        do {
            resolved = try await preparation.prepare(
                item: item,
                initial: initialMediaSource,
                profile: deviceProfile,
                maxBitrate: maxBitrate,
                audio: audioStreamIndex,
                subtitle: subtitleStreamIndex
            )
        } catch is PlaybackPreparationError { throw ErrorMessage(L10n.unknownError) }
        #endif
        try preparation.checkBinding()
        item = resolved.item
        let mediaSource = resolved.source
        let playSessionID = resolved.playSessionID
        let playbackURL = resolved.url

        // Bind every image load to the transport that prepared this item.
        // A replacement account, URL or credential invalidates the old provider.
        let previewClient = transport
        let previewIsCurrent: @MainActor @Sendable () -> Bool = { [weak userSession, weak previewClient] in
            guard let userSession, let previewClient,
                  Container.shared.userSessionManager().currentSession === userSession else { return false }
            return userSession.client === previewClient
        }
        let previewImageProvider: (any PreviewImageProvider)? = {
            let setting = StoredValues[.User.previewImageScrubbing]
            lazy var chapters: ChapterPreviewImageProvider? = {
                guard let source = item.fullChapterInfo,
                      source.contains(where: { $0.imageSource?.url != nil }) else { return nil }
                return ChapterPreviewImageProvider(
                    chapters: source.map { PreviewChapter(start: $0.chapterInfo.startSeconds, url: $0.imageSource?.url) },
                    isCurrent: previewIsCurrent
                ) { url in
                    try? await preparation.image(url: url)
                }
            }()
            if case let .trickplay(fallbackToChapters) = setting {
                if let sourceID = mediaSource.id,
                   let info = item.trickplay?[sourceID]?.first?.value,
                   let layout = TrickplayPreviewLayout(
                       columns: info.tileWidth ?? 0,
                       rows: info.tileHeight ?? 0,
                       width: info.width ?? 0,
                       intervalMilliseconds: info.interval ?? 1000,
                       runtime: item.runtime ?? .zero
                   )
                {
                    return TrickplayPreviewImageProvider(layout: layout, isCurrent: previewIsCurrent) { index in
                        try? await preparation.trickplayImage(itemID: itemID, width: layout.width, index: index, sourceID: sourceID)
                    }
                }
                return fallbackToChapters ? chapters : nil
            }
            return setting == .chapters ? chapters : nil
        }()

        let trackPolicy = MediaTrackPolicy(
            mediaSource: mediaSource,
            deviceProfile: deviceProfile,
            compatibility: compatibilityMode,
            audioIndex: audioStreamIndex,
            subtitleIndex: subtitleStreamIndex
        )
        let sidecars = try preparation.sidecarSubtitles(from: trackPolicy.subtitleStreams)

        return .init(
            baseItem: item,
            mediaSource: mediaSource,
            playSessionID: playSessionID,
            url: playbackURL,
            requestedBitrate: requestedBitrate,
            deviceProfile: deviceProfile,
            sidecarSubtitles: sidecars,
            compatibilityMode: compatibilityMode,
            initialAudioStreamIndex: audioStreamIndex,
            initialSubtitleStreamIndex: subtitleStreamIndex,
            previewImageProvider: previewImageProvider,
            thumbnailProvider: item.getNowPlayingImage
        )
    }
}
