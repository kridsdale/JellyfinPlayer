//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Defaults
import Get
import JellyfinAPI
import SwiftfinCollections
import SwiftfinLocalization
import SwiftUI

final class ItemContentGroupProvider: ViewModel, ContentGroupProvider {

    @Published
    private(set) var item: BaseItemDto
    @Published
    private(set) var localTrailers: [BaseItemDto] = []
    @Published
    private(set) var mediaPlayerItemProvider: MediaPlayerItemProvider?
    @Published
    private(set) var randomBackdropItem: BaseItemDto?

    @Published
    var isPresentingDeleteConfirmation = false

    nonisolated let id: String

    var displayTitle: String {
        item.displayTitle
    }

    init(item: BaseItemDto) {
        self.id = item.id ?? "Unknown"
        self.item = item
        super.init()
    }

    init(id: String) {
        self.id = id
        self.item = .init(id: id)
        super.init()
    }

    func makeGroups(environment: Empty) async throws -> [any ContentGroup] {
        let session = try requireUserSession()
        let catalog = session.mediaCatalog
        let fullItem = try await catalog.item(id: id)
        let playbackItem = try await catalog.playbackSelection(for: fullItem)
        let newLocalTrailers = try? await catalog.localTrailers(itemID: fullItem.id ?? id)
        let newRandomBackdropItem = try? await catalog.randomBackdrop(for: fullItem)
        try catalog.checkBinding()
        item = fullItem
        localTrailers = newLocalTrailers ?? []
        mediaPlayerItemProvider = playbackItem?.getPlaybackItemProvider(userSession: session)
        randomBackdropItem = newRandomBackdropItem
        Notifications[.itemMetadataDidChange].post(fullItem)
        let groups = try await _makeGroups(item: fullItem, itemID: id)
        try catalog.checkBinding()
        return groups
    }

    @ContentGroupBuilder
    private func _makeGroups(item: BaseItemDto, itemID: String) async throws -> [any ContentGroup] {

        if let birthday = item.birthday?.formatted(date: .long, time: .omitted) {
            LabeledContentGroup(
                L10n.born,
                value: birthday
            )
        }

        if let deathday = item.deathday?.formatted(date: .long, time: .omitted) {
            LabeledContentGroup(
                L10n.died,
                value: deathday
            )
        }

        if let birthplace = item.birthplace {
            LabeledContentGroup(
                L10n.birthplace,
                value: birthplace
            )
        }

        switch item.type {
        case .season, .series:
            SeriesEpisodeContentGroup(
                parent: item,
                playButtonItem: mediaPlayerItemProvider?.item
            )
        default:
            []
        }

        if let genres = item.itemGenres, genres.isNotEmpty {
            PillGroup(
                displayTitle: L10n.genres,
                id: "genres",
                elements: genres
            ) { router, element in
                router.route(
                    to: .contentGroup(
                        provider: ItemTypeContentGroupProvider(
                            itemTypes: [
                                BaseItemKind.movie,
                                .series,
                                .boxSet,
                                .episode,
                                .musicVideo,
                                .video,
                                .liveTvProgram,
                                .tvChannel,
                                .person,
                            ],
                            parent: BaseItemDto(name: element.displayTitle),
                            environment: .init(filters: .init(genres: [element]))
                        )
                    )
                )
            }
        }

        if let studios = item.studios, studios.isNotEmpty {
            PillGroup(
                displayTitle: L10n.studios,
                id: "studios",
                elements: studios
            ) { router, element in
                router.route(
                    to: .contentGroup(
                        provider: ItemTypeContentGroupProvider(
                            itemTypes: [
                                BaseItemKind.movie,
                                .series,
                                .boxSet,
                                .episode,
                                .musicVideo,
                                .video,
                                .liveTvProgram,
                                .tvChannel,
                                .person,
                            ],
                            parent: BaseItemDto(id: element.id, name: element.displayTitle, type: .studio)
                        )
                    )
                )
            }
        }

        switch item.type {
        case .movie:
            if item.partCount ?? 0 > 1 {
                PosterGroup(
                    id: "additional-parts",
                    library: AdditionalPartsLibrary(itemID: itemID),
                    posterDisplayType: .landscape,
                    posterSize: .small
                )
            }
        case .boxSet, .person, .musicArtist:
            try await ItemTypeContentGroupProvider(
                itemTypes: BaseItemKind.supportedCases
                    .appending(.episode)
                    .appending(.person),
                parent: item
            )
            .makeGroups(environment: .default)
        case .series:
            try await ItemTypeContentGroupProvider(
                itemTypes: [.season],
                parent: item
            )
            .makeGroups(environment: .default)
        case .channel, .liveTvChannel, .tvChannel:
            PosterGroup(
                id: "channel-programs",
                library: ChannelScheduleLibrary(channel: item),
                posterDisplayType: .landscape,
                posterSize: .small
            )
        default: []
        }

        if item.type == .episode {
            PosterGroup(
                library: StaticLibrary(
                    title: L10n.season,
                    id: "seasons",
                    elements: [BaseItemDto(
                        id: item.seasonID,
                        imageTags: item.parentPrimaryImageItemID == item.seasonID
                            ? item.parentPrimaryImageTag.map { [ImageType.primary.rawValue: $0] }
                            : nil,
                        name: item.seasonName,
                        parentBackdropImageTags: item.parentBackdropImageTags,
                        parentBackdropItemID: item.parentBackdropItemID,
                        parentThumbImageTag: item.parentThumbImageTag,
                        parentThumbItemID: item.parentThumbItemID,
                        seriesID: item.seriesID,
                        seriesName: item.seriesName,
                        seriesPrimaryImageTag: item.seriesPrimaryImageTag,
                        seriesThumbImageTag: item.seriesThumbImageTag,
                        type: .season
                    )]
                ),
                posterSize: .small,
                environment: .init(isHeaderButtonEnabled: false)
            )
        }

        if let castAndCrew = item.mergedPeople, castAndCrew.isNotEmpty {
            PosterGroup(
                id: "cast-and-crew",
                library: StaticLibrary(
                    title: L10n.castAndCrew.localizedCapitalized,
                    id: "cast-and-crew",
                    elements: castAndCrew
                ),
                posterDisplayType: .portrait,
                posterSize: .small
            )
        }

        PosterGroup(
            id: "special-features",
            library: SpecialFeaturesLibrary(itemID: itemID),
            posterDisplayType: .landscape,
            posterSize: .small
        )

        if Defaults[.Customization.shouldShowRecommendations] {
            PosterGroup(
                id: "similar-items",
                library: SimilarItemsLibrary(itemID: itemID, itemType: item.type),
                posterDisplayType: .landscape,
                posterSize: .small
            )
        }

        AboutItemGroup(
            displayTitle: L10n.about,
            id: "about",
            item: item
        )
    }

    func toggleIsFavorite() async {
        let beforeIsFavorite = item.userData?.isFavorite ?? false

        item.userData?.isFavorite = !beforeIsFavorite
        do {
            try await setIsFavorite(!beforeIsFavorite)
        } catch {
            item.userData?.isFavorite = beforeIsFavorite
        }
    }

    func toggleIsPlayed() async {
        let beforeIsPlayed = item.userData?.isPlayed ?? false

        item.userData?.isPlayed = !beforeIsPlayed
        do {
            try await setIsPlayed(!beforeIsPlayed)
        } catch {
            item.userData?.isPlayed = beforeIsPlayed
        }
    }

    enum PlaybackSelection {
        case mediaSource(MediaSourceInfo?)
        case audioStreamIndex(Int?)
        case subtitleStreamIndex(Int?)
        case bitrate(PlaybackBitrate)
    }

    func select(_ selection: PlaybackSelection) {
        guard let provider = mediaPlayerItemProvider, let userSession else { return }

        var mediaSource = provider.mediaSource
        var audioStreamIndex = provider.audioStreamIndex
        var subtitleStreamIndex = provider.subtitleStreamIndex
        var requestedBitrate = provider.requestedBitrate

        switch selection {
        case let .mediaSource(source):
            mediaSource = source
            audioStreamIndex = nil
            subtitleStreamIndex = nil
        case let .audioStreamIndex(index):
            audioStreamIndex = index
        case let .subtitleStreamIndex(index):
            subtitleStreamIndex = index
        case let .bitrate(bitrate):
            requestedBitrate = bitrate
        }

        mediaPlayerItemProvider = provider.item.getPlaybackItemProvider(
            userSession: userSession,
            mediaSource: mediaSource,
            audioStreamIndex: audioStreamIndex,
            subtitleStreamIndex: subtitleStreamIndex,
            requestedBitrate: requestedBitrate
        )
    }

    private func setIsPlayed(_ isPlayed: Bool) async throws {
        guard let itemID = item.id else { return }

        let request: Request<UserItemDataDto> = if isPlayed {
            try Paths.markPlayedItem(
                itemID: itemID,
                userID: authenticatedUser.id
            )
        } else {
            try Paths.markUnplayedItem(
                itemID: itemID,
                userID: authenticatedUser.id
            )
        }

        let response = try await send(request)
        Notifications[.itemUserDataDidChange].post(response.value)
        Notifications[.itemShouldRefreshMetadata].post(itemID)
    }

    private func setIsFavorite(_ isFavorite: Bool) async throws {
        guard let itemID = item.id else { return }

        let request: Request<UserItemDataDto> = if isFavorite {
            try Paths.markFavoriteItem(
                itemID: itemID,
                userID: authenticatedUser.id
            )
        } else {
            try Paths.unmarkFavoriteItem(
                itemID: itemID,
                userID: authenticatedUser.id
            )
        }

        let response = try await send(request)
        Notifications[.itemUserDataDidChange].post(response.value)
        Notifications[.itemShouldRefreshMetadata].post(itemID)
    }
}
