//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation
import JellyfinAPI

public enum MediaCatalogPolicy {
    public static let itemFields: [ItemFields] = [.mediaStreams, .genres, .studios]
    public static let defaultItemTypes: [BaseItemKind] = [.boxSet, .movie, .musicVideo, .series, .video]
    public static let supportedCollectionTypes: [CollectionType] = [
        .boxsets,
        .folders,
        .homevideos,
        .movies,
        .musicvideos,
        .tvshows,
        .livetv
    ]

    /// Preserve the single-kind group query workaround without changing other queries.
    public static func groupedItemTypes(for kind: BaseItemKind) -> [BaseItemKind] {
        kind == .boxSet ? [.boxSet, .userView] : [kind]
    }

    public static func itemTypes(parentType: BaseItemKind?, collectionType: CollectionType?, groupingID: String?) -> [BaseItemKind] {
        switch (collectionType, parentType) {
        case (_, .folder): defaultItemTypes + [.folder, .collectionFolder]
        case (_, .channel), (_, .liveTvChannel), (_, .tvChannel): [.liveTvProgram]
        case (.movies, _): [.movie]
        case (.tvshows, _): groupingID == "episodes" ? [.episode] : groupingID == "seasons" ? [.season] : [.series]
        case (.music, _): [.audio, .musicAlbum, .musicArtist]
        default: defaultItemTypes
        }
    }

    public static func isRecursive(parentType: BaseItemKind?, collectionType: CollectionType?, groupingID: String?) -> Bool {
        guard let collectionType, parentType != .userView else { return true }
        if groupingID == "episodes" || groupingID == "seasons" {
            return true
        }
        return ![.tvshows, .boxsets].contains(collectionType)
    }

    public static func normalize(_ rows: [BaseItemDto], parentType: BaseItemKind?) -> CatalogPage {
        let items = rows.filter { $0.collectionType.map(supportedCollectionTypes.contains) ?? true }.map { row in
            var row = row
            if parentType == .folder && row.type == .collectionFolder {
                row.type = .folder
            }
            return row
        }
        return CatalogPage(items: items, consumedCount: rows.count)
    }

    public static func normalizeViews(_ rows: [BaseItemDto], excludedIDs: [String]) -> [BaseItemDto] {
        rows.compactMap { row in
            var row = row
            if row.collectionType == nil {
                row.collectionType = .folders
            }
            guard let collection = row.collectionType, supportedCollectionTypes.contains(collection),
                  !(row.id.map { excludedIDs.contains($0) } ?? false) else { return nil }
            if row.type == .userView && collection == .folders {
                row.type = .folder
            }
            return row
        }
    }

    public static func itemParameters(_ query: CatalogItemQuery, userID: String, page: CatalogPageRequest, mode: CatalogItemMode) -> Paths
    .GetItemsParameters {
        let filters = query.filters
        var p = Paths.GetItemsParameters()
        p.enableUserData = true
        p.fields = itemFields
        p.includeItemTypes = itemTypes(parentType: query.parentType, collectionType: query.collectionType, groupingID: query.groupingID)
        p.isRecursive = isRecursive(parentType: query.parentType, collectionType: query.collectionType, groupingID: query.groupingID)
        if let id = query.parentID {
            switch query.parentType {
            case .folder: p.parentID = id
                p.isRecursive = nil
            case .person: p.personIDs = [id]
            case .studio: p.studioIDs = [id]
            default: p.parentID = id
            }
        }
        p.audioLanguages = filters.audioLanguages
        p.filters = filters.traits
        p.genres = filters.genres
        p.officialRatings = filters.officialRatings
        p.sortBy = filters.sortBy
        p.sortOrder = filters.sortOrder
        p.subtitleLanguages = filters.subtitleLanguages
        p.tags = filters.tags
        p.years = filters.years.compactMap(Int.init)
        p.isMovie = filters.categories.contains(.movies) ? true : nil
        p.isSeries = filters.categories.contains(.series) ? true : nil
        p.isNews = filters.categories.contains(.news) ? true : nil
        p.isKids = filters.categories.contains(.kids) ? true : nil
        p.isSports = filters.categories.contains(.sports) ? true : nil
        p.searchTerm = filters.query
        if !filters.itemTypes.isEmpty {
            p.includeItemTypes = filters.itemTypes
        }
        if let letter = filters.letter {
            if letter == "#" {
                p.nameLessThan = "A"
            } else {
                p.nameStartsWith = letter
            }
        }
        p.limit = page.limit
        p.startIndex = page.offset
        p.userID = userID
        switch mode {
        case .browse: break
        case let .search(query, staticQuery): p.searchTerm = staticQuery ?? query
        case .random: p.limit = 1
            p.startIndex = nil
            p.sortBy = [.random]
        }
        return p
    }

    public static func isScheduled(_ timer: TimerInfoDto, now: Date) -> Bool {
        switch timer.status {
        case .inProgress: true
        case .cancelled, .completed, .error: false
        default: (timer.endDate ?? .distantFuture) > now
        }
    }
}
