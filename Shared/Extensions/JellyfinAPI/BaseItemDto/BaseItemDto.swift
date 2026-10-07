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
import MediaPlayer
import Nuke
import SwiftfinCollections
import SwiftfinFilters
import SwiftfinImages
import SwiftfinItemMetadata
import SwiftfinLocalization
import SwiftfinMediaCatalog
import SwiftfinMediaTracks
import SwiftfinNowPlaying
import SwiftfinPlaybackPreparation
import SwiftfinRecordingTimers
import SwiftfinText
import SwiftfinTime
import SwiftfinUserMediaState
import SwiftfinValues
import SwiftUI

extension BaseItemDto {

    init(person: BaseItemPerson) {
        self.init(
            id: person.id,
            imageTags: person.primaryImageTag.map { [ImageType.primary.rawValue: $0] },
            name: person.name,
            type: .person
        )
        self.people = [person]
    }
}

extension BaseItemDto: Displayable {

    var displayTitle: String {
        name ?? L10n.unknown
    }
}

extension BaseItemDto {

    @MainActor
    func nowPlayableStaticMetadata(_ image: UIImage? = nil) -> NowPlayableStaticMetadata {

        let mediaType: MPNowPlayingInfoMediaType = {
            switch type {
            case .audio, .audioBook: .audio
            default: .video
            }
        }()

        let title: String = {
            if type == .episode,
               let seriesName
            {
                seriesName
            } else {
                displayTitle
            }
        }()

        let albumArtist: String? = {
            switch type {
            case .audio:
                artists?.joined(separator: ", ")
            default:
                nil
            }
        }()

        let albumTitle: String? = {
            switch type {
            case .audio:
                album
            default:
                nil
            }
        }()

        // TODO: only fill artist, albumArtist, and albumTitle if audio type
        return .init(
            mediaType: mediaType,
            isLiveStream: isLiveStream,
            title: title,
            artist: subtitle,
            artwork: image.map(NowPlayingArtwork.make),
            albumArtist: albumArtist,
            albumTitle: albumTitle
        )
    }

    var birthday: Date? {
        ItemMetadataFacts(self).birthday
    }

    var birthplace: String? {
        ItemMetadataFacts(self).birthplace
    }

    var deathday: Date? {
        ItemMetadataFacts(self).deathday
    }

    var episodeLocator: String? {
        guard let episodeNo = indexNumber else { return nil }
        return L10n.episodeNumber(episodeNo)
    }

    /// Merges crew credits
    var mergedPeople: [BaseItemPerson]? {
        ItemMetadataPolicy.mergedPeople(in: self)
    }

    var itemGenres: [ItemGenre]? {
        guard let genres else { return nil }
        return genres.map(ItemGenre.init)
    }

    /// Differs from `isLive` to indicate an item
    /// would be streaming from a live source.
    var isLiveStream: Bool {
        CatalogItemState(self, at: .now).isLiveStream
    }

    var isAiring: Bool {
        CatalogItemState(self, at: .now).isAiring
    }

    /// Whether the item has independent playable content, similar
    /// to if an item can provide its own media sources.
    ///
    /// ie: A movie and an episode can be directly played,
    ///     but a series is not as its episodes are playable.
    var isPlayable: Bool {
        CatalogItemState(self, at: .now).isPlayable
    }

    /// The primary image handler for building the
    /// image used in the now playing system.
    @MainActor
    func getNowPlayingImage(preparation: PlaybackPreparationClient? = nil) async -> UIImage? {
        do { try Task.checkCancellation()
            try preparation?.checkBinding()
        } catch { return nil }
        // Source URLs are materialized synchronously while this connection is current.
        let imageSources = imageSources(
            for: preferredPosterDisplayType,
            size: .small,
            environment: .init(useParent: true)
        )

        let firstImage = await ImagePipeline.Swiftfin.other.loadFirstImage(from: imageSources)
        do { try Task.checkCancellation()
            try preparation?.checkBinding()
        } catch { return nil }
        guard let firstImage else {
            let failedSystemContentView = SystemImageContentView(
                systemName: systemImage
            )
            .posterStyle(preferredPosterDisplayType)
            .frame(width: 400)

            return ImageRenderer(content: failedSystemContentView).uiImage
        }

        let image = Image(uiImage: firstImage)
            .resizable()
        let transformedImage = ZStack {
            Rectangle()
                .fill(Color.secondarySystemFill)

            transform(image: image, displayType: preferredPosterDisplayType)
        }
        .posterAspectRatio(preferredPosterDisplayType, contentMode: .fit)
        .frame(width: 400)

        return ImageRenderer(content: transformedImage).uiImage
    }

    @MainActor
    func getPlaybackItemProvider(
        userSession: UserSession?,
        mediaSource: MediaSourceInfo? = nil,
        audioStreamIndex: Int? = nil,
        subtitleStreamIndex: Int? = nil,
        requestedBitrate: PlaybackBitrate = Defaults[.VideoPlayer.Playback.appMaximumBitrate]
    ) -> MediaPlayerItemProvider? {
        guard let session = userSession ?? Container.shared.currentUserSession() else { return nil }
        let connection = session.playbackConnection
        do { try connection.preparation.checkBinding() }
        catch { return nil }
        switch type {
        case .program:
            guard isAiring, userSession != nil else { return nil }

            return MediaPlayerItemProvider(item: self) { program, modifyItem in
                guard let channel = try? await program.getChannel(
                    for: program,
                    userSession: session
                ) else {
                    throw ErrorMessage(L10n.unknownError)
                }

                return try await MediaPlayerItem.build(
                    for: channel,
                    connection: connection,
                    modifyItem: modifyItem
                )
            }
        default:
            let selectedMediaSource = mediaSource ?? mediaSources?.first

            return MediaPlayerItemProvider(
                item: self,
                mediaSource: selectedMediaSource,
                audioStreamIndex: audioStreamIndex,
                subtitleStreamIndex: subtitleStreamIndex,
                requestedBitrate: requestedBitrate
            ) { item, modifyItem in
                try await MediaPlayerItem.build(
                    for: item,
                    connection: connection,
                    mediaSource: selectedMediaSource,
                    audioStreamIndex: audioStreamIndex,
                    subtitleStreamIndex: subtitleStreamIndex,
                    requestedBitrate: requestedBitrate,
                    modifyItem: modifyItem
                )
            }
        }
    }

    @MainActor
    func getChannel(
        for program: BaseItemDto,
        userSession: UserSession
    ) async throws -> BaseItemDto? {
        guard type == .program else { return nil }

        guard let channelID = program.channelID, !channelID.isEmpty else { return nil }
        return try await userSession.mediaCatalog.channel(id: channelID)
    }

    var runtime: Duration? {
        CatalogItemState(self, at: .now).runtime
    }

    var startSeconds: Duration? {
        CatalogItemState(self, at: .now).startSeconds
    }

    var seasonEpisodeLabel: String? {
        guard let seasonNo = parentIndexNumber, let episodeNo = indexNumber else { return nil }
        return L10n.seasonAndEpisode(String(seasonNo), String(episodeNo))
    }

    // MARK: Calculations

    var runTimeLabel: String? {
        let timeHMSFormatter: DateComponentsFormatter = {
            let formatter = DateComponentsFormatter()
            formatter.unitsStyle = .abbreviated
            formatter.allowedUnits = [.hour, .minute]
            return formatter
        }()

        guard let runTimeTicks,
              let text = timeHMSFormatter.string(from: Double(runTimeTicks / 10_000_000)) else { return nil }

        return text
    }

    var progressLabel: String? {
        if let currentProgram {
            return currentProgram.progressLabel
        }

        let interval: TimeInterval

        if let playbackPositionTicks = userData?.playbackPositionTicks,
           let totalTicks = runTimeTicks,
           playbackPositionTicks != 0,
           totalTicks != 0
        {
            interval = TimeInterval((totalTicks - playbackPositionTicks) / 10_000_000)
        } else if isAiring, let startDate {
            interval = Date.now.timeIntervalSince(startDate)
        } else {
            return nil
        }

        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute]
        formatter.unitsStyle = .abbreviated

        return formatter.string(from: interval)
    }

    var programDuration: TimeInterval? {
        CatalogItemState(self, at: .now).programDuration
    }

    var programProgress: Double? {
        CatalogItemState(self, at: .now).programProgress
    }

    func programProgress(relativeTo other: Date) -> Double? {
        CatalogItemState(self, at: other).programProgress
    }

    var progressPercentage: Double? {
        CatalogItemState(self, at: .now).progressPercentage
    }

    var subtitleStreams: [MediaStream] {
        MediaStreamKindPolicy.streams(in: mediaStreams, matching: .subtitle)
    }

    var audioStreams: [MediaStream] {
        MediaStreamKindPolicy.streams(in: mediaStreams, matching: .audio)
    }

    var videoStreams: [MediaStream] {
        MediaStreamKindPolicy.streams(in: mediaStreams, matching: .video)
    }

    var isRecording: Bool {
        CatalogItemState(self, at: .now).isRecording
    }

    // MARK: Missing and Unaired

    var isMissing: Bool {
        CatalogItemState(self, at: .now).isMissing
    }

    var isUnaired: Bool {
        CatalogItemState(self, at: .now).isUnaired
    }

    var hasAired: Bool {
        CatalogItemState(self, at: .now).hasAired
    }

    var airDateLabel: String? {
        guard let premiereDateFormatted = premiereDateLabel else { return nil }
        return L10n.airWithDate(premiereDateFormatted)
    }

    var premiereDateLabel: String? {
        guard let premiereDate else { return nil }

        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        return dateFormatter.string(from: premiereDate)
    }

    var premiereDateYear: String? {
        guard let premiereDate else { return nil }
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "YYYY"
        return dateFormatter.string(from: premiereDate)
    }

    var hasExternalLinks: Bool {
        ItemMetadataFacts(self).hasExternalLinks
    }

    var hasRatings: Bool {
        ItemMetadataFacts(self).hasRatings
    }

    // MARK: Chapter Images

    @MainActor
    var fullChapterInfo: [ChapterInfo.FullInfo]? {

        guard let chapters = chapters?
            .sorted(using: \.startPositionTicks)
            .compacted(using: \.startPositionTicks) else { return nil }

        guard let userSession = Container.shared.currentUserSession() else { return nil }

        return chapters
            .enumerated()
            .map { i, chapter in

                guard let imageTag = chapter.imageTag, imageTag.isNotEmpty else {
                    return .init(chapterInfo: chapter)
                }

                let imageURL = ItemImageURLPolicy.url(
                    using: userSession.client,
                    itemID: id ?? "",
                    type: ImageType.chapter.rawValue,
                    index: i,
                    tag: imageTag,
                    maxWidth: 500,
                    quality: 90
                )

                return .init(
                    chapterInfo: chapter,
                    imageSource: .init(url: imageURL)
                )
            }
    }

    /// Returns `originalTitle` if it is not the same as `displayTitle`
    var alternateTitle: String? {
        originalTitle != displayTitle ? originalTitle : nil
    }

    /// Can this `BaseItemDto` be played
    @MainActor
    var presentPlayButton: Bool {
        CatalogItemState(self, at: .now)
            .presentsPlayButton(permitted: Container.shared.currentUserSession()?.user.data.policy?.enableMediaPlayback == true)
    }

    /// Can this `BaseItemDto` be favorited
    var canBeFavorited: Bool {
        UserMediaStatePolicy.capabilities(for: type).canBeFavorited
    }

    /// Can this `BaseItemDto` be mark as played
    var canBePlayed: Bool {
        UserMediaStatePolicy.capabilities(for: type).canBePlayed
    }

    /// Can this `BaseItemDto` be recorded
    @MainActor
    var canBeRecorded: Bool {
        RecordingTimerPolicy.canRecord(
            self,
            permitted: Container.shared.currentUserSession()?.user.data.policy?.enableLiveTvManagement == true,
            now: .now
        )
    }

    @MainActor
    var playButtonLabel: String {

        if isUnaired {
            return L10n.unaired
        }

        if hasAired {
            return L10n.ended
        }

        if isMissing {
            return L10n.missing
        }

        if let progressLabel {
            return progressLabel
        }

        return L10n.play
    }

    /// Label for the parent's type
    var parentLabel: String? {
        switch type {
        case .audio:
            L10n.album
        case .episode, .season:
            L10n.series
        case .musicAlbum:
            L10n.artist
        default:
            nil
        }
    }

    var parentTitle: String? {
        CatalogItemState(self, at: .now).parentTitle
    }

    var parentRootID: String? {
        CatalogItemState(self, at: .now).parentRootID
    }

    /// Does this `BaseItemDto` have `Genres`, `People`, `Studios`, or `Tags`
    var hasComponents: Bool {
        ItemMetadataFacts(self).hasComponents
    }

    @MainActor
    func getFullItem(
        userSession: UserSession,
        sendNotification: Bool = false,
        taskDelegate: URLSessionDataDelegate? = nil
    ) async throws -> BaseItemDto {
        guard let id else {
            throw ErrorMessage(L10n.unknownError)
        }

        let metadata = userSession.itemMetadata
        let item = try await metadata.item(id: id, delegate: taskDelegate)
        try metadata.checkBinding()

        // A check against `id` would typically be done, but a plugin
        // may have provided `self` or the response item and may not
        // be invariant over `id`.

        if sendNotification {
            Notifications[.itemMetadataDidChange].post(item)
        }

        return item
    }
}
