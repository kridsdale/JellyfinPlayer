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
    private let urls: (any JellyfinURLResolving)?
    public let bindingID: MetadataBindingID
    public init(
        executor: AuthenticatedRequestExecutor,
        userID: String,
        bindingID: MetadataBindingID,
        urls: (any JellyfinURLResolving)? = nil
    ) {
        self.executor = executor
        self.userID = userID
        self.urls = urls
        self.bindingID = bindingID
    }

    public func checkBinding() throws {
        try executor.checkBinding()
    }

    /// Resolves through the originally supplied transport and rechecks reentrant resolvers.
    public func imageURL(itemID: String, image: ImageInfo) throws -> URL? {
        try checkBinding()
        guard let urls else { return nil }
        let url = ItemImageURLPolicy.url(
            using: urls,
            itemID: itemID,
            type: image.imageType?.rawValue ?? "",
            index: image.imageIndex,
            tag: image.imageTag
        )
        try checkBinding()
        return url
    }

    public func item(id: String, delegate: (any URLSessionDataDelegate)? = nil) async throws -> BaseItemDto {
        try await executor.value(for: Paths.getItem(itemID: id, userID: userID), delegate: delegate)
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

    /// One captured transport owns apply then reload. Validate before each stage
    /// and before returning; cancellation cannot undo an already accepted apply.
    public func applyIdentityAndReload(
        itemID: String,
        result: RemoteSearchResult,
        validate: @MainActor @Sendable () throws -> Void = {}
    ) async throws -> BaseItemDto {
        try checkBinding()
        try validate()
        try await applyIdentity(itemID: itemID, result: result)
        try checkBinding()
        try validate()
        let updated = try await item(id: itemID)
        try checkBinding()
        try validate()
        return updated
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

    /// Captured update then reload, with caller relevance checked at each stage.
    /// A reload failure cannot undo an update already accepted by the server.
    public func updateAndReload(
        itemID: String,
        item: BaseItemDto,
        validate: @MainActor @Sendable () throws -> Void = {}
    ) async throws -> BaseItemDto {
        try checkBinding()
        try validate()
        try await update(itemID: itemID, item: item)
        try checkBinding()
        try validate()
        let updated = try await self.item(id: itemID)
        try checkBinding()
        try validate()
        return updated
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

public extension ItemMetadataClient {
    func itemImages(itemID: String) async throws -> [ImageType: [ImageInfo]] {
        let images = try await executor.value(for: Paths.getItemImageInfos(itemID: itemID))
        return Self.groupImages(images)
    }

    static func groupImages(_ images: [ImageInfo]) -> [ImageType: [ImageInfo]] {
        var grouped: [ImageType: [ImageInfo]] = [:]
        for image in images {
            guard let type = image.imageType else { continue }
            grouped[type, default: []].append(image)
        }
        return grouped.mapValues { values in
            values.sorted { lhs, rhs in
                if let a = lhs.imageIndex, let b = rhs.imageIndex {
                    return a < b
                }
                return lhs.imageIndex != nil && rhs.imageIndex == nil
            }
        }
    }

    func uploadImage(itemID: String, type: ImageType, data: Data, contentType: String) async throws {
        var request = Paths.setItemImage(itemID: itemID, imageType: type.rawValue, data.base64EncodedData())
        request.headers = ["Content-Type": contentType]
        try await executor.complete(request)
    }

    @discardableResult
    func saveRemoteImage(itemID: String, image: RemoteImageInfo) async throws -> Bool {
        try checkBinding()
        guard let type = image.type, let url = image.url else { return false }
        try await executor.complete(Paths.downloadRemoteImage(itemID: itemID, type: type, imageURL: url))
        return true
    }

    @discardableResult
    func deleteImage(itemID: String, image: ImageInfo) async throws -> Bool {
        try checkBinding()
        guard let type = image.imageType else { return false }
        if let index = image.imageIndex {
            try await executor.complete(Paths.deleteItemImageByIndex(itemID: itemID, imageType: type.rawValue, imageIndex: index))
        } else {
            try await executor.complete(Paths.deleteItemImage(itemID: itemID, imageType: type.rawValue))
        }
        return true
    }
}
