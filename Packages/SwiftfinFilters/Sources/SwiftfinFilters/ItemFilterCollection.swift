//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation
import JellyfinAPI
import SwiftfinMediaCatalog

public struct ItemFilterCollection: Codable, Hashable, Sendable {

    public var audioLanguages: [ItemLanguage] = []
    public var categories: [ChannelCategory] = []
    public var genres: [ItemGenre] = []
    public var itemTypes: [BaseItemKind] = []
    public var letter: [ItemLetter] = []
    public var officialRatings: [ItemOfficialRating] = []
    public var sortBy: [ItemSortBy] = [ItemSortBy.sortName]
    public var sortOrder: [JellyfinAPI.SortOrder] = [JellyfinAPI.SortOrder.ascending]
    public var subtitleLanguages: [ItemLanguage] = []
    public var tags: [ItemTag] = []
    public var traits: [JellyfinAPI.ItemFilter] = []
    public var years: [ItemYear] = []

    public var query: String?

    public init(
        audioLanguages: [ItemLanguage] = [], categories: [ChannelCategory] = [], genres: [ItemGenre] = [],
        itemTypes: [BaseItemKind] = [], letter: [ItemLetter] = [], officialRatings: [ItemOfficialRating] = [],
        sortBy: [ItemSortBy] = [.sortName], sortOrder: [JellyfinAPI.SortOrder] = [.ascending],
        subtitleLanguages: [ItemLanguage] = [], tags: [ItemTag] = [], traits: [JellyfinAPI.ItemFilter] = [],
        years: [ItemYear] = [], query: String? = nil
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

    public mutating func reset(_ type: ItemFilterType?) {
        guard let type else { self = .default
            return
        }
        switch type {
        case .audioLanguage: audioLanguages = Self.default.audioLanguages
        case .category: categories = Self.default.categories
        case .genres: genres = Self.default.genres
        case .letter: letter = Self.default.letter
        case .officialRatings: officialRatings = Self.default.officialRatings
        case .sortBy: sortBy = Self.default.sortBy
            sortOrder = Self.default.sortOrder
        case .subtitleLanguage: subtitleLanguages = Self.default.subtitleLanguages
        case .tags: tags = Self.default.tags
        case .traits: traits = Self.default.traits
        case .years: years = Self.default.years
        }
    }

    /// The default collection of filters
    public static let `default`: ItemFilterCollection = .init()

    public static let favorites: ItemFilterCollection = .init(
        traits: [JellyfinAPI.ItemFilter.isFavorite]
    )
    public static let recent: ItemFilterCollection = .init(
        sortBy: [ItemSortBy.dateCreated],
        sortOrder: [JellyfinAPI.SortOrder.descending]
    )

    public var isNotEmpty: Bool {
        self != Self.default
    }

    public var hasQueryableFilters: Bool {
        !audioLanguages.isEmpty ||
            !categories.isEmpty ||
            !genres.isEmpty ||
            !itemTypes.isEmpty ||
            !letter.isEmpty ||
            !officialRatings.isEmpty ||
            !subtitleLanguages.isEmpty ||
            !tags.isEmpty ||
            !traits.isEmpty ||
            !years.isEmpty ||
            !(query?.isEmpty ?? true)
    }

    public func containsFilters(ofType type: ItemFilterType) -> Bool {
        switch type {
        case .audioLanguage: audioLanguages != Self.default.audioLanguages
        case .category: categories != Self.default.categories
        case .genres: genres != Self.default.genres
        case .letter: letter != Self.default.letter
        case .officialRatings: officialRatings != Self.default.officialRatings
        case .sortBy: sortBy != Self.default.sortBy || sortOrder != Self.default.sortOrder
        case .subtitleLanguage: subtitleLanguages != Self.default.subtitleLanguages
        case .tags: tags != Self.default.tags
        case .traits: traits != Self.default.traits
        case .years: years != Self.default.years
        }
    }

    /// The union of this collection and another collection, with
    /// precedence given to this collection's values.
    public func union(_ other: Self) -> Self {
        var result = other

        func apply(_ keyPath: WritableKeyPath<Self, some Equatable>) {
            if self[keyPath: keyPath] != Self.default[keyPath: keyPath] {
                result[keyPath: keyPath] = self[keyPath: keyPath]
            }
        }

        apply(\.audioLanguages)
        apply(\.categories)
        apply(\.genres)
        apply(\.itemTypes)
        apply(\.letter)
        apply(\.officialRatings)
        apply(\.subtitleLanguages)
        apply(\.tags)
        apply(\.traits)
        apply(\.years)
        apply(\.query)

        if containsFilters(ofType: .sortBy) {
            result.sortBy = sortBy
            result.sortOrder = sortOrder
        }

        return result
    }
}

public extension ItemFilterCollection {
    var catalogSnapshot: CatalogFilters {
        CatalogFilters(
            audioLanguages: audioLanguages.map(\.value),
            categories: categories.compactMap { MediaProgramCategory(rawValue: $0.rawValue) },
            genres: genres.map(\.value),
            itemTypes: itemTypes,
            letter: letter.first?.value,
            officialRatings: officialRatings.map(\.value),
            sortBy: sortBy,
            sortOrder: sortOrder,
            subtitleLanguages: subtitleLanguages.map(\.value),
            tags: tags.map(\.value),
            traits: traits,
            years: years.map(\.value),
            query: query
        )
    }
}
