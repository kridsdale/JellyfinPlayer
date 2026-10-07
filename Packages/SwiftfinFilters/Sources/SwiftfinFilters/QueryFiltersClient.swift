//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation
import JellyfinAPI
import SwiftfinNetworking

public struct DiscoveredModernFilters: Sendable {
    public let audioLanguages: [ItemLanguage]
    public let genres: [ItemGenre]
    public let subtitleLanguages: [ItemLanguage]
    public let tags: [ItemTag]
    public func applying(to existing: ItemFilterCollection) -> ItemFilterCollection {
        var result = existing
        result.audioLanguages = audioLanguages
        result.genres = genres
        result.subtitleLanguages = subtitleLanguages
        result.tags = tags
        return result
    }
}

public struct DiscoveredLegacyFilters: Sendable {
    public let officialRatings: [ItemOfficialRating]
    public let years: [ItemYear]
    public func applying(to existing: ItemFilterCollection) -> ItemFilterCollection {
        var result = existing
        result.officialRatings = officialRatings
        result.years = years
        return result
    }
}

/// The two discovery stages share one immutable authenticated executor/user.
@MainActor
public final class QueryFiltersClient {
    private let executor: AuthenticatedRequestExecutor
    private let userID: String
    public init(executor: AuthenticatedRequestExecutor, userID: String) {
        self.executor = executor
        self.userID = userID
    }

    public func checkBinding() throws {
        try executor.checkBinding()
    }

    public func modern(parentID: String?, itemTypes: [BaseItemKind]) async throws -> DiscoveredModernFilters {
        let request = Paths.getQueryFilters(parameters: .init(
            userID: userID,
            parentID: parentID,
            includeItemTypes: itemTypes,
            isRecursive: true
        ))
        let response = try await executor.value(for: request)
        return DiscoveredModernFilters(
            audioLanguages: (response.audioLanguages ?? []).compactMap(ItemLanguage.init).sorted { $0.displayTitle < $1.displayTitle },
            genres: (response.genres ?? []).compactMap(\.name).map { ItemGenre(stringLiteral: $0) },
            subtitleLanguages: (response.subtitleLanguages ?? []).compactMap(ItemLanguage.init)
                .sorted { $0.displayTitle < $1.displayTitle },
            tags: (response.tags ?? []).map { ItemTag(stringLiteral: $0) }
        )
    }

    public func legacy(parentID: String?, itemTypes: [BaseItemKind]) async throws -> DiscoveredLegacyFilters {
        let request = Paths.getQueryFiltersLegacy(parameters: .init(userID: userID, parentID: parentID, includeItemTypes: itemTypes))
        let response = try await executor.value(for: request)
        return DiscoveredLegacyFilters(
            officialRatings: (response.officialRatings ?? []).map { ItemOfficialRating(stringLiteral: $0) },
            years: (response.years ?? []).sorted(by: >).map { ItemYear(integerLiteral: $0) }
        )
    }
}
