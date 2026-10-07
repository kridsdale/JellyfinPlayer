//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation
import JellyfinAPI

public enum MediaProgramCategory: String, CaseIterable, Codable, Hashable, Sendable {
    case kids
    case movies
    case news
    case series
    case sports
}

public struct CatalogPageRequest: Equatable, Sendable {
    public let offset: Int
    public let limit: Int
    public init(offset: Int, limit: Int) {
        self.offset = max(0, offset)
        self.limit = max(1, limit)
    }
}

public struct CatalogPage: Sendable {
    public let items: [BaseItemDto]
    public let consumedCount: Int
    public init(items: [BaseItemDto], consumedCount: Int? = nil) {
        self.items = items
        self.consumedCount = max(items.count, consumedCount ?? items.count)
    }
}

public struct CatalogFilters: Sendable {
    public let audioLanguages: [String]
    public let categories: [MediaProgramCategory]
    public let genres: [String]
    public let itemTypes: [BaseItemKind]
    public let letter: String?
    public let officialRatings: [String]
    public let sortBy: [ItemSortBy]
    public let sortOrder: [JellyfinAPI.SortOrder]
    public let subtitleLanguages: [String]
    public let tags: [String]
    public let traits: [JellyfinAPI.ItemFilter]
    public let years: [String]
    public let query: String?
    public init(
        audioLanguages: [String] = [],
        categories: [MediaProgramCategory] = [],
        genres: [String] = [],
        itemTypes: [BaseItemKind] = [],
        letter: String? = nil,
        officialRatings: [String] = [],
        sortBy: [ItemSortBy] = [.sortName],
        sortOrder: [JellyfinAPI.SortOrder] = [.ascending],
        subtitleLanguages: [String] = [],
        tags: [String] = [],
        traits: [JellyfinAPI.ItemFilter] = [],
        years: [String] = [],
        query: String? = nil
    ) {
        self.audioLanguages = audioLanguages
        self.categories = categories
        self.genres = genres
        self.itemTypes = itemTypes
        self.letter = letter
        self.officialRatings = officialRatings
        self.sortBy = sortBy
        self.sortOrder = sortOrder
        self.subtitleLanguages = subtitleLanguages
        self.tags = tags
        self.traits = traits
        self.years = years
        self.query = query
    }
}

public struct CatalogItemQuery: Sendable {
    public let parentID: String?
    public let parentType: BaseItemKind?
    public let collectionType: CollectionType?
    public let groupingID: String?
    public let filters: CatalogFilters
    public init(
        parentID: String?,
        parentType: BaseItemKind?,
        collectionType: CollectionType?,
        groupingID: String? = nil,
        filters: CatalogFilters = .init()
    ) {
        self.parentID = parentID
        self.parentType = parentType
        self.collectionType = collectionType
        self.groupingID = groupingID
        self.filters = filters
    }
}

public enum CatalogItemMode: Sendable {
    case browse
    case search(query: String, staticQuery: String?)
    case random
}

/// Media metadata only. The client has no file, credential or playback mutators.
public enum MediaCatalogQuery: Sendable {
    case items(CatalogItemQuery, mode: CatalogItemMode = .browse)
    case recent
    case latest(parentID: String?)
    case nextUp(rewatching: Bool, maximumAge: TimeInterval, now: Date)
    case resume(mediaTypes: [MediaType])
    case recordings
    case programs(category: MediaProgramCategory)
    case recommendedPrograms
    case people(query: String?)
    case genres
    case channels
    case channelSchedule(channelID: String?, from: Date)
    case seasons(seriesID: String, showMissing: Bool)
    case episodes(seasonID: String, showMissing: Bool)
    case additionalParts(itemID: String)
    case specialFeatures(itemID: String)
    case localTrailers(itemID: String)
    case similar(itemID: String, itemType: BaseItemKind?)
    case scheduledRecordings
    case artworkSample(parentID: String?, itemTypes: [BaseItemKind], favorites: Bool)

    public var supportsPagination: Bool {
        switch self {
        case .latest, .seasons, .episodes, .additionalParts, .specialFeatures, .localTrailers, .similar, .scheduledRecordings,
             .artworkSample: false
        case .items(_, .random): false
        default: true
        }
    }
}
