//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation
import Get
import JellyfinAPI
import SwiftfinCollections
import SwiftfinNetworking

@MainActor
public protocol MediaCatalogReading {
    func read<Value: Decodable & Sendable>(_ request: Request<Value>) async throws -> Value
}

extension JellyfinTransport: MediaCatalogReading {
    public func read<Value: Decodable & Sendable>(_ request: Request<Value>) async throws -> Value {
        guard request.method == .get else { throw MediaCatalogError.nonReadRequest }
        return try await send(request).value
    }
}

/// Composition injects one exact transport/user pair; it is never replaced in flight.
@MainActor
public final class MediaCatalogClient {
    private let reader: any MediaCatalogReading
    private let userID: String
    private let isCurrent: @MainActor @Sendable () -> Bool
    private let now: @MainActor @Sendable () -> Date
    public init(
        reader: any MediaCatalogReading,
        userID: String,
        now: @escaping @MainActor @Sendable () -> Date = { .now },
        isCurrent: @escaping @MainActor @Sendable () -> Bool = { true }
    ) {
        self.isCurrent = isCurrent
        self.reader = reader
        self.userID = userID
        self.now = now
    }

    public func checkBinding() throws {
        try Task.checkCancellation()
        guard isCurrent() else { throw CancellationError() }
    }

    private func read<Value: Decodable & Sendable>(_ request: Request<Value>) async throws -> Value {
        try checkBinding()
        guard request.method == .get else { throw MediaCatalogError.nonReadRequest }
        do {
            let result = try await reader.read(request)
            try checkBinding()
            return result
        } catch {
            try checkBinding()
            throw error
        }
    }

    public func userViews() async throws -> [BaseItemDto] {
        async let views = read(Paths.getUserViews(parameters: .init(userID: userID)))
        async let user = read(Paths.getCurrentUser)
        return try await MediaCatalogPolicy.normalizeViews(views.items ?? [], excludedIDs: user.configuration?.myMediaExcludes ?? [])
    }

    public func page(_ query: MediaCatalogQuery, at page: CatalogPageRequest) async throws -> CatalogPage {
        try checkBinding()
        if !query.supportsPagination && page.offset != 0 {
            return CatalogPage(items: [])
        }
        switch query {
        case let .items(input, mode):
            let p = MediaCatalogPolicy.itemParameters(input, userID: userID, page: page, mode: mode)
            let rows = try await read(Paths.getItems(parameters: p)).items ?? []
            if case .random = mode {
                return CatalogPage(items: rows)
            }
            return MediaCatalogPolicy.normalize(rows, parentType: input.parentType)
        case .recent:
            var p = Paths.GetItemsParameters()
            p.enableUserData = true
            p.fields = MediaCatalogPolicy.itemFields
            p.includeItemTypes = [.movie, .series]
            p.isRecursive = true
            p.limit = page.limit
            p.startIndex = page.offset
            p.sortBy = [.dateCreated]
            p.sortOrder = [.descending]
            p.userID = userID
            return try await CatalogPage(items: read(Paths.getItems(parameters: p)).items ?? [])
        case let .latest(parentID):
            var p = Paths.GetLatestMediaParameters()
            p.enableUserData = true
            p.fields = MediaCatalogPolicy.itemFields
            p.limit = page.limit
            p.parentID = parentID
            p.userID = userID
            return try await CatalogPage(items: read(Paths.getLatestMedia(parameters: p)))
        case let .nextUp(rewatching, maximumAge, now):
            var p = Paths.GetNextUpParameters()
            p.enableRewatching = rewatching
            p.enableUserData = true
            p.fields = MediaCatalogPolicy.itemFields
            p.limit = page.limit
            p.startIndex = page.offset
            if maximumAge.isFinite && maximumAge > 0 {
                p.nextUpDateCutoff = now.addingTimeInterval(-maximumAge)
            }
            return try await CatalogPage(items: read(Paths.getNextUp(parameters: p)).items ?? [])
        case let .resume(mediaTypes):
            var p = Paths.GetResumeItemsParameters()
            p.enableUserData = true
            p.fields = MediaCatalogPolicy.itemFields
            p.limit = page.limit
            p.startIndex = page.offset
            p.mediaTypes = mediaTypes
            p.userID = userID
            return try await CatalogPage(items: read(Paths.getResumeItems(parameters: p)).items ?? [])
        case .recordings:
            var p = Paths.GetRecordingsParameters()
            p.fields = MediaCatalogPolicy.itemFields
            p.userID = userID
            p.startIndex = page.offset
            p.limit = page.limit
            p.enableUserData = true
            p.isInProgress = false
            return try await CatalogPage(items: read(Paths.getRecordings(parameters: p)).items ?? [])
        case let .programs(category):
            var p = Paths.GetLiveTvProgramsParameters()
            p.fields = [.channelInfo]
            p.hasAired = false
            p.limit = page.limit
            p.startIndex = page.offset
            p.userID = userID
            p.isKids = category == .kids
            p.isMovie = category == .movies
            p.isNews = category == .news
            p.isSeries = category == .series
            p.isSports = category == .sports
            return try await CatalogPage(items: read(Paths.getLiveTvPrograms(parameters: p)).items ?? [])
        case .recommendedPrograms:
            var p = Paths.GetRecommendedProgramsParameters()
            p.fields = [.channelInfo]
            p.isAiring = true
            p.limit = page.limit
            p.startIndex = page.offset
            p.userID = userID
            return try await CatalogPage(items: read(Paths.getRecommendedPrograms(parameters: p)).items ?? [])
        case let .people(query):
            var p = Paths.GetPersonsParameters()
            p.limit = page.limit
            p.startIndex = page.offset
            p.searchTerm = query
            return try await CatalogPage(items: read(Paths.getPersons(parameters: p)).items ?? [])
        case .genres:
            var p = Paths.GetGenresParameters()
            p.limit = page.limit
            p.startIndex = page.offset
            return try await CatalogPage(items: read(Paths.getGenres(parameters: p)).items ?? [])
        case .channels:
            var p = Paths.GetLiveTvChannelsParameters()
            p.limit = page.limit
            p.startIndex = page.offset
            p.userID = userID
            return try await CatalogPage(items: read(Paths.getLiveTvChannels(parameters: p)).items ?? [])
        case let .channelSchedule(channelID, from):
            var p = Paths.GetLiveTvProgramsParameters()
            p.channelIDs = [channelID].compactMap(\.self)
            p.fields = [.channelInfo]
            p.limit = page.limit
            p.minEndDate = from
            p.sortBy = [.startDate]
            p.startIndex = page.offset
            p.userID = userID
            return try await CatalogPage(items: read(Paths.getLiveTvPrograms(parameters: p)).items ?? [])
        case let .seasons(seriesID, showMissing):
            var p = Paths.GetSeasonsParameters()
            p.fields = MediaCatalogPolicy.itemFields
            p.isMissing = showMissing ? nil : false
            p.userID = userID
            return try await CatalogPage(items: read(Paths.getSeasons(seriesID: seriesID, parameters: p)).items ?? [])
        case let .episodes(seasonID, showMissing):
            var p = Paths.GetEpisodesParameters()
            p.enableUserData = true
            p.fields = MediaCatalogPolicy.itemFields + [.overview]
            p.isMissing = showMissing ? nil : false
            p.seasonID = seasonID
            p.userID = userID
            return try await CatalogPage(items: read(Paths.getEpisodes(seriesID: seasonID, parameters: p)).items ?? [])
        case let .additionalParts(id): return try await CatalogPage(items: read(Paths.getAdditionalPart(itemID: id)).items ?? [])
        case let .specialFeatures(id): return try await CatalogPage(items: read(Paths.getSpecialFeatures(itemID: id)))
        case let .localTrailers(id): return try await CatalogPage(items: read(Paths.getLocalTrailers(itemID: id, userID: userID)))
        case let .similar(id, type):
            var p = Paths.GetSimilarItemsParameters()
            p.fields = MediaCatalogPolicy.itemFields
            p.limit = page.limit
            p.userID = userID
            if let type, [.liveTvProgram, .program, .tvProgram].contains(type) {
                p.fields = MediaCatalogPolicy.itemFields + [.channelInfo]
            }
            return try await CatalogPage(items: read(Paths.getSimilarItems(itemID: id, parameters: p)).items ?? [])
        case .scheduledRecordings:
            let timers = try await read(Paths.getTimers()).items ?? []
            let responseTime = now()
            let items = timers.filter { MediaCatalogPolicy.isScheduled($0, now: responseTime) }.sorted(using: \.startDate)
                .compactMap(\.programInfo)
            return CatalogPage(items: items, consumedCount: timers.count)
        case let .artworkSample(parentID, itemTypes, favorites):
            var p = Paths.GetItemsParameters()
            p.filters = favorites ? [.isFavorite] : nil
            p.includeItemTypes = itemTypes
            p.isRecursive = true
            p.limit = 3
            p.parentID = parentID
            p.sortBy = [.random]
            p.userID = userID
            return try await CatalogPage(items: read(Paths.getItems(parameters: p)).items ?? [])
        }
    }
}

public enum MediaCatalogError: Error, Sendable { case nonReadRequest }

public struct AdjacentEpisodes: Sendable {
    public let previous: BaseItemDto?
    public let next: BaseItemDto?
    public init(previous: BaseItemDto?, next: BaseItemDto?) {
        self.previous = previous
        self.next = next
    }

    public static func resolve(_ items: [BaseItemDto], currentID: String) -> AdjacentEpisodes {
        guard let index = items.firstIndex(where: { $0.id == currentID }) else { return .init(previous: nil, next: nil) }
        let previous = index > 0 ? items[index - 1] : nil
        let next = index + 1 < items.count ? items[index + 1] : nil
        return .init(previous: previous, next: next)
    }
}

public extension MediaCatalogClient {
    func item(id: String) async throws -> BaseItemDto {
        try await read(Paths.getItem(itemID: id, userID: userID))
    }

    func homeViews(excludedIDs: [String]) async throws -> [BaseItemDto] {
        let response = try await read(Paths.getUserViews(parameters: .init(userID: userID)))
        return (response.items ?? []).filter {
            !excludedIDs.contains($0.id ?? "") && [.homevideos, .movies, .musicvideos, .tvshows].contains($0.collectionType)
        }
    }

    func suggestions(fields: [ItemFields]) async throws -> [BaseItemDto] {
        var p = Paths.GetItemsParameters()
        p.fields = fields
        p.includeItemTypes = [.movie, .series]
        p.isRecursive = true
        p.limit = 10
        p.sortBy = [.random]
        p.userID = userID
        return try await read(Paths.getItems(parameters: p)).items ?? []
    }

    func playbackSelection(for item: BaseItemDto) async throws -> BaseItemDto? {
        try checkBinding()
        let candidate: BaseItemDto?
        switch item.type {
        case .series:
            guard let id = item.id else { return nil }
            var next = Paths.GetNextUpParameters()
            next.seriesID = id
            next.userID = userID
            let first = try await read(Paths.getNextUp(parameters: next)).items?.first
            if let first, first.locationType != .virtual {
                candidate = first
            } else if let resumed = try await resumeCandidate(parentID: id) {
                candidate = resumed
            } else {
                candidate = try await firstCandidate(parentID: id)
            }
        case .season:
            guard let id = item.id else { return nil }
            if let resumed = try await resumeCandidate(parentID: id) {
                candidate = resumed
            } else {
                candidate = try await firstCandidate(parentID: id)
            }
        default:
            return item.locationType == .virtual ? nil : item
        }
        guard let id = candidate?.id else { return nil }
        return try await self.item(id: id)
    }

    private func resumeCandidate(parentID: String) async throws -> BaseItemDto? {
        var p = Paths.GetResumeItemsParameters()
        p.limit = 1
        p.parentID = parentID
        p.userID = userID
        return try await read(Paths.getResumeItems(parameters: p)).items?.first
    }

    private func firstCandidate(parentID: String) async throws -> BaseItemDto? {
        var p = Paths.GetItemsParameters()
        p.includeItemTypes = [.episode]
        p.isMissing = false
        p.isRecursive = true
        p.limit = 1
        p.parentID = parentID
        p.sortOrder = [.ascending]
        p.userID = userID
        return try await read(Paths.getItems(parameters: p)).items?.first
    }

    func localTrailers(itemID: String) async throws -> [BaseItemDto] {
        try await read(Paths.getLocalTrailers(itemID: itemID, userID: userID))
    }

    func randomBackdrop(for item: BaseItemDto) async throws -> BaseItemDto? {
        try checkBinding()
        guard [.person, .musicArtist, .boxSet].contains(item.type), let id = item.id else { return nil }
        var p = Paths.GetItemsParameters()
        p.includeItemTypes = [.movie, .series]
        p.isRecursive = true
        p.limit = 1
        p.sortBy = [.random]
        p.userID = userID
        if item.type == .person {
            p.personIDs = [id]
        } else {
            p.parentID = id
        }
        return try await read(Paths.getItems(parameters: p)).items?.first
    }

    func adjacentEpisodes(for item: BaseItemDto) async throws -> AdjacentEpisodes {
        try checkBinding()
        guard item.type == .episode, let seriesID = item.seriesID, let itemID = item.id else { return .init(previous: nil, next: nil) }
        var p = Paths.GetEpisodesParameters()
        p.userID = userID
        p.adjacentTo = itemID
        p.limit = 3
        let items = try await read(Paths.getEpisodes(seriesID: seriesID, parameters: p)).items ?? []
        return .resolve(items, currentID: itemID)
    }

    func programs(channelIDs: [String], startDate: Date, endDate: Date) async throws -> [BaseItemDto] {
        try checkBinding()
        guard !channelIDs.isEmpty else { return [] }
        var p = Paths.GetLiveTvProgramsParameters()
        p.channelIDs = channelIDs
        p.enableImages = false
        p.enableTotalRecordCount = false
        p.enableUserData = false
        p.maxStartDate = endDate
        p.minEndDate = startDate
        p.sortBy = [.startDate]
        p.userID = userID
        return try await read(Paths.getLiveTvPrograms(parameters: p)).items ?? []
    }
}
