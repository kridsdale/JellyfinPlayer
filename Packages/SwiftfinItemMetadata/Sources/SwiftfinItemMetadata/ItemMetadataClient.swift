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
import SwiftfinNetworking

@MainActor
public final class ItemMetadataClient {
    private let executor: AuthenticatedRequestExecutor
    private let userID: String
    public let bindingID: MetadataBindingID
    public init(executor: AuthenticatedRequestExecutor, userID: String, bindingID: MetadataBindingID) {
        self.executor = executor
        self.userID = userID
        self.bindingID = bindingID
    }

    public func checkBinding() throws {
        try executor.checkBinding()
    }

    public func item(id: String) async throws -> BaseItemDto {
        try await executor.value(for: Paths.getItem(itemID: id, userID: userID))
    }

    public func countries() async throws -> [CountryInfo] {
        try await executor.value(for: Paths.getCountries)
    }

    public func cultures() async throws -> [CultureDto] {
        try await executor.value(for: Paths.getCultures)
    }

    public func parentalRatings() async throws -> [ParentalRating] {
        try await executor.value(for: Paths.getParentalRatings)
    }

    public func imageProviders(itemID: String) async throws -> [ImageProviderInfo] {
        try await executor
            .value(for: Paths.getRemoteImageProviders(itemID: itemID))
    }

    public func remoteImages(
        itemID: String,
        type: ImageType,
        includeAllLanguages: Bool,
        provider: String?,
        offset: Int,
        limit: Int
    ) async throws -> [RemoteImageInfo] {
        var p = Paths.GetRemoteImagesParameters()
        p.isIncludeAllLanguages = includeAllLanguages
        p.providerName = provider
        p.type = type
        p.startIndex = max(0, offset)
        p.limit = max(1, limit)
        return try await executor.value(for: Paths.getRemoteImages(itemID: itemID, parameters: p)).images ?? []
    }

    public func identityResults(itemID: String, itemType: BaseItemKind, query: MetadataSearchQuery) async throws -> [RemoteSearchResult] {
        try checkBinding()
        guard !query.isEmpty else { return [] }
        let name = query.name
        let originalTitle = query.originalTitle
        let year = query.year
        switch itemType {
        case .boxSet:
            let parameters = BoxSetInfoRemoteSearchQuery(
                itemID: itemID,
                searchInfo: .init(
                    name: name,
                    originalTitle: originalTitle,
                    year: year
                )
            )
            let request = Paths.getBoxSetRemoteSearchResults(parameters)
            return try await executor.value(for: request)

        case .movie:
            let parameters = MovieInfoRemoteSearchQuery(
                itemID: itemID,
                searchInfo: .init(
                    name: name,
                    originalTitle: originalTitle,
                    year: year
                )
            )
            let request = Paths.getMovieRemoteSearchResults(parameters)
            return try await executor.value(for: request)

        case .person:
            let parameters = PersonLookupInfoRemoteSearchQuery(
                itemID: itemID,
                searchInfo: .init(
                    name: name,
                    originalTitle: originalTitle,
                    year: year
                )
            )
            let request = Paths.getPersonRemoteSearchResults(parameters)
            return try await executor.value(for: request)

        case .series:
            let parameters = SeriesInfoRemoteSearchQuery(
                itemID: itemID,
                searchInfo: .init(
                    name: name,
                    originalTitle: originalTitle,
                    year: year
                )
            )
            let request = Paths.getSeriesRemoteSearchResults(parameters)
            return try await executor.value(for: request)

        default:
            return []
        }
    }

    public func applyIdentity(itemID: String, result: RemoteSearchResult) async throws {
        try await executor.complete(Paths.applySearchCriteria(
            itemID: itemID,
            result
        ))
    }

    public func deleteItem(id: String) async throws {
        try await executor.complete(Paths.deleteItem(itemID: id))
    }

    public func refresh(itemID: String, options: MetadataRefreshOptions) async throws {
        var p = Paths.RefreshItemParameters()
        p.metadataRefreshMode = options.metadataMode
        p.imageRefreshMode = options.imageMode
        p.isReplaceAllMetadata = options.replaceMetadata
        p.isReplaceAllImages = options.replaceImages
        p.isRegenerateTrickplay = options.regenerateTrickplay
        try await executor.complete(Paths.refreshItem(itemID: itemID, parameters: p))
    }

    public func update(itemID: String, item: BaseItemDto) async throws {
        try await executor.complete(Paths.updateItem(
            itemID: itemID,
            ItemMetadataPolicy.updatePayload(item)
        ))
    }

    public func searchSubtitles(itemID: String, language: String, perfectMatch: Bool) async throws -> [RemoteSubtitleInfo] {
        try checkBinding()
        guard !language.isEmpty else { return [] }
        return try await executor.value(for: Paths.searchRemoteSubtitles(itemID: itemID, language: language, isPerfectMatch: perfectMatch))
    }

    public func downloadSubtitles(itemID: String, subtitleIDs: Set<String>) async throws {
        try checkBinding()
        try await withThrowingTaskGroup(of: Void.self) { group in
            for id in subtitleIDs.sorted() {
                group.addTask { try await self.executor.complete(Paths.downloadRemoteSubtitles(
                    itemID: itemID,
                    subtitleID: id
                )) }
            }
            try await group.waitForAll()
        }
        try checkBinding()
    }

    public func uploadSubtitle(
        itemID: String,
        data: Data,
        format: String,
        language: String,
        forced: Bool,
        hearingImpaired: Bool
    ) async throws {
        let subtitle = UploadSubtitleDto(
            data: data.base64EncodedString(),
            format: format,
            isForced: forced,
            isHearingImpaired: hearingImpaired,
            language: language
        )
        try await executor.complete(Paths.uploadSubtitle(itemID: itemID, subtitle))
    }

    public func deleteSubtitles(itemID: String, indices: Set<Int>) async throws {
        try checkBinding()
        for index in indices.sorted(by: >) {
            do { try await executor.complete(Paths.deleteSubtitle(itemID: itemID, index: index)) }
            catch is CancellationError { throw CancellationError() }
            catch { throw MetadataSubtitleDeletionFailure(index: index, underlying: error) }
        }
        try checkBinding()
    }

    public func genreMatches(query: String) async throws -> [String] {
        let p = Paths.GetGenresParameters(searchTerm: query.isEmpty ? nil : query)
        return try await executor.value(for: Paths.getGenres(parameters: p)).items?.compactMap(\.name) ?? []
    }

    public func studioMatches(query: String) async throws -> [NameIDPair] {
        let p = Paths.GetStudiosParameters(searchTerm: query.isEmpty ? nil : query)
        return try await executor.value(for: Paths.getStudios(parameters: p)).items?.map { NameIDPair(id: $0.id, name: $0.name) } ?? []
    }

    public func peopleMatches(query: String) async throws -> [BaseItemPerson] {
        let p = Paths.GetPersonsParameters(searchTerm: query.isEmpty ? nil : query)
        return try await executor.value(for: Paths.getPersons(parameters: p)).items?.map { BaseItemPerson(id: $0.id, name: $0.name) } ?? []
    }

    public func tags() async throws -> [String] {
        try await executor.value(for: Paths.getQueryFiltersLegacy(parameters: .init(userID: userID))).tags ?? []
    }
}
