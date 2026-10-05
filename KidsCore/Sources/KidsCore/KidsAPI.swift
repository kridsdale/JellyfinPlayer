//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

// SPDX-License-Identifier: MPL-2.0
import Foundation

public enum KidsAPIError: Error, LocalizedError, Equatable {
    case authentication
    case policy
    case libraryChanged
    case unavailable
    case connection
    case invalidResponse
    public var errorDescription: String? {
        switch self {
        case .authentication: "A grown-up needs to sign in again."
        case .policy: "Use an account with access only to Kid TV and Kid Movies, without administration or deletion."
        case .libraryChanged: "The approved libraries have changed. A grown-up needs to check setup."
        case .unavailable: "This video is unavailable."
        case .connection: "We cannot reach your TV library right now."
        case .invalidResponse: "The library needs a grown-up to check it."
        }
    }
}

public struct KidsServerInfo: Codable, Sendable {
    public let id: String
    public let name: String
    enum CodingKeys: String, CodingKey { case id = "Id", name = "ServerName" }
}

public struct KidsLibrary: Codable, Identifiable, Sendable {
    public let id: String
    public let name: String
    public let collectionType: String?
    enum CodingKeys: String, CodingKey { case id = "Id", name = "Name", collectionType = "CollectionType" }
}

public struct KidsLibraryPage: Codable, Sendable {
    public let items: [KidsLibrary]
    enum CodingKeys: String, CodingKey { case items = "Items" }
}

private struct UserResponse: Decodable {
    var id: String
    var policy: Policy
    struct Policy: Decodable {
        var isAdministrator: Bool?
        var enableAllFolders: Bool?
        var enableContentDeletion: Bool?
        var enabledFolders: [String]?
        enum CodingKeys: String, CodingKey {
            case isAdministrator = "IsAdministrator"
            case enableAllFolders = "EnableAllFolders"
            case enableContentDeletion = "EnableContentDeletion", enabledFolders = "EnabledFolders"
        }
    }

    enum CodingKeys: String, CodingKey { case id = "Id", policy = "Policy" }
}

private struct ItemAncestor: Decodable {
    let id: String
    enum CodingKeys: String, CodingKey { case id = "Id" }
}

private struct ItemPage: Decodable {
    var items: [ItemResponse]
    var total: Int?
    enum CodingKeys: String, CodingKey { case items = "Items", total = "TotalRecordCount" }
}

private struct ItemResponse: Decodable {
    var id: String
    var name: String
    var type: String
    var seriesID: String?
    var season: Int?
    var episode: Int?
    var runtime: Double?
    var imageTags: [String: String]?
    var seriesImageTag: String?
    var locationType: String?
    enum CodingKeys: String, CodingKey {
        case id = "Id"
        case name = "Name"
        case type = "Type"
        case seriesID = "SeriesId"
        case season = "ParentIndexNumber", episode = "IndexNumber", runtime = "RunTimeTicks"
        case imageTags = "ImageTags", seriesImageTag = "SeriesPrimaryImageTag", locationType = "LocationType"
    }

    func item(libraryID: String) -> KidsItem? {
        guard let kind = KidsItem.Kind(rawValue: type.lowercased()), locationType != "Virtual" else { return nil }
        return KidsItem(
            id: id,
            name: name,
            kind: kind,
            libraryID: libraryID,
            seriesID: seriesID,
            season: season,
            episode: episode,
            runtime: runtime.map { $0 / 10_000_000 },
            imageTag: imageTags?["Primary"] ?? seriesImageTag,
            imageOwnerID: imageTags?["Primary"] == nil ? seriesID : id
        )
    }
}

/// All catalog reads are scoped to the explicit parent-approved library binding.
/// Ephemeral, uncached requests prevent a previous account's catalog being replayed offline.
public struct KidsAPI: Sendable {
    public let serverURL: URL
    public let token: String
    private let session: URLSession
    public init(serverURL: URL, token: String, session: URLSession? = nil) {
        self.serverURL = serverURL
        self.token = token
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 20
        config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        self.session = session ?? URLSession(configuration: config)
    }

    public func serverInfo() async throws -> KidsServerInfo {
        try await get("System/Info/Public")
    }

    public func libraries(userID: String) async throws -> [KidsLibrary] {
        let page: KidsLibraryPage = try await get("Users/\(userID)/Views")
        return page.items
    }

    public func validate(_ binding: KidsBinding) async throws {
        let trace = KidsPerformance.begin(.policy)
        do {
            let result: Void = try await KidsPerformance.$current.withValue(trace) {
                let info = try await serverInfo()
                guard info.id == binding.serverID else { throw KidsAPIError.libraryChanged }
                let user: UserResponse = try await get("Users/Me")
                guard user.id == binding.userID else { throw KidsAPIError.authentication }
                let policy = KidsAccessPolicy(
                    administrator: user.policy.isAdministrator ?? true,
                    allLibraries: user.policy.enableAllFolders ?? true,
                    deletion: user.policy.enableContentDeletion ?? true,
                    enabledLibraries: Set(user.policy.enabledFolders ?? [])
                )
                guard policy.permits(binding) else { throw KidsAPIError.policy }
                let libs = try await libraries(userID: binding.userID)
                guard Set(libs.map(\.id)) == binding.libraryIDs,
                      libs.contains(where: { $0.id == binding.showsID && $0.collectionType == "tvshows" }),
                      libs.contains(where: { $0.id == binding.moviesID && $0.collectionType == "movies" })
                else {
                    throw KidsAPIError.libraryChanged
                }
            }
            trace?.finish()
            return result
        } catch { trace?.finish(error: error)
            throw error
        }
    }

    public func catalog(_ category: KidsCategory, binding: KidsBinding) async throws -> [KidsItem] {
        let trace = KidsPerformance.begin(.catalog, variant: category == .shows ? .shows : .movies)
        do {
            let result = try await KidsPerformance.$current.withValue(trace) {
                let candidates = try await items(
                    libraryID: binding.library(for: category),
                    binding: binding,
                    extra: ["IncludeItemTypes": category == .shows ? "Series" : "Movie"]
                )
                .filter { KidsEligibility.permits($0, binding: binding) && $0.kind == (category == .shows ? .series : .movie) }
                return try await verified(candidates, libraryID: binding.library(for: category), binding: binding)
            }
            trace?.finish()
            return result
        } catch { trace?.finish(error: error)
            throw error
        }
    }

    public func episodes(showID: String, binding: KidsBinding) async throws -> [KidsItem] {
        let trace = KidsPerformance.begin(.episodes)
        do {
            let result = try await KidsPerformance.$current.withValue(trace) {
                try await authorize(itemID: showID, expectedKind: .series, binding: binding)
                // The dedicated endpoint limits pagination to this already-authorized
                // show. Series identity, regular numbering and library ancestry are
                // still verified locally; the endpoint is not an authorization boundary.
                let values = try await episodeItems(showID: showID, binding: binding)
                let eligible = try KidsEligibility.episodes(values, showID: showID, binding: binding)
                let checked = try await verified(eligible, libraryID: binding.showsID, binding: binding)
                guard !checked.isEmpty else { throw KidsContractError.unavailable }
                return checked
            }
            trace?.finish()
            return result
        } catch { trace?.finish(error: error)
            throw error
        }
    }

    @discardableResult
    public func authorize(itemID: String, expectedKind: KidsItem.Kind, binding: KidsBinding) async throws -> KidsItem {
        let trace = KidsPerformance.begin(.authorize)
        do {
            let result = try await KidsPerformance.$current.withValue(trace) {
                try await validate(binding)
                let library = expectedKind == .movie ? binding.moviesID : binding.showsID
                let values = try await items(libraryID: library, binding: binding, extra: ["Ids": itemID])
                guard let item = values.first(where: { $0.id == itemID && $0.kind == expectedKind }),
                      KidsEligibility.permits(item, binding: binding) else { throw KidsContractError.denied }
                try await verifyMembership(item.id, libraryID: library, binding: binding)
                return item
            }
            trace?.finish()
            return result
        } catch { trace?.finish(error: error)
            throw error
        }
    }

    /// The scoped Items response is not itself proof of membership. Confirm ancestry
    /// before any title or artwork enters the catalog, including forged upstream IDs.
    private func verifyMembership(_ itemID: String, libraryID: String, binding: KidsBinding) async throws {
        let ancestors: [ItemAncestor] = try await get("Items/\(itemID)/Ancestors", query: ["userId": binding.userID])
        guard ancestors.contains(where: { $0.id == libraryID }) else { throw KidsContractError.denied }
    }

    private func verified(_ items: [KidsItem], libraryID: String, binding: KidsBinding) async throws -> [KidsItem] {
        let trace = KidsPerformance.begin(.ancestry)
        do {
            let result = try await KidsPerformance.$current.withValue(trace) {
                try await withThrowingTaskGroup(of: (Int, Bool).self) { group in
                    var next = 0
                    var approved = Set<Int>()
                    func add(_ index: Int) {
                        group.addTask {
                            do { try await verifyMembership(items[index].id, libraryID: libraryID, binding: binding)
                                return (index, true)
                            } catch KidsContractError.denied { return (index, false) }
                            catch KidsAPIError.unavailable { return (index, false) }
                        }
                    }
                    while next < min(8, items.count) {
                        add(next)
                        next += 1
                    }
                    for try await (index, allowed) in group {
                        if allowed {
                            approved.insert(index)
                        }
                        if next < items.count {
                            add(next)
                            next += 1
                        }
                    }
                    return items.enumerated().compactMap { approved.contains($0.offset) ? $0.element : nil }
                }
            }
            trace?.finish()
            return result
        } catch { trace?.finish(error: error)
            throw error
        }
    }

    private func items(libraryID: String, binding: KidsBinding, extra: [String: String]) async throws -> [KidsItem] {
        guard binding.isValid && binding.libraryIDs.contains(libraryID) else { throw KidsContractError.denied }
        var result: [KidsItem] = []
        var start = 0
        var ids = Set<String>()
        while true {
            var query = [
                "ParentId": libraryID,
                "UserId": binding.userID,
                "Recursive": "true",
                "Fields": "PrimaryImageAspectRatio",
                "SortBy": "SortName",
                "SortOrder": "Ascending",
                "StartIndex": String(start),
                "Limit": "200"
            ]
            query.merge(extra) { _, new in new }
            let page: ItemPage = try await get("Items", query: query)
            for raw in page.items {
                if let item = raw.item(libraryID: libraryID) {
                    let inserted = ids.insert(item.id).inserted
                    if !inserted && extra["IncludeItemTypes"] == "Episode" {
                        throw KidsContractError.ambiguousEpisodes
                    }
                    if inserted {
                        result.append(item)
                    }
                }
            }
            start += page.items.count
            if page.items.isEmpty || start >= (page.total ?? start) {
                break
            }
            guard start < 100_000 else { throw KidsAPIError.invalidResponse }
        }
        return result
    }

    private func episodeItems(showID: String, binding: KidsBinding) async throws -> [KidsItem] {
        guard binding.isValid, !showID.isEmpty,
              showID.utf8
                  .allSatisfy({ (48 ... 57).contains($0) || (65 ... 90).contains($0) || (97 ... 122).contains($0) || $0 == 45 || $0 == 95 })
        else { throw KidsContractError.denied }
        var values: [KidsItem] = []
        var seen = Set<String>()
        var start = 0
        while true {
            try Task.checkCancellation()
            let page: ItemPage = try await get("Shows/\(showID)/Episodes", query: [
                "UserId": binding.userID, "StartIndex": String(start), "Limit": "200",
                "Fields": "PrimaryImageAspectRatio"
            ])
            for raw in page.items {
                if let item = raw.item(libraryID: binding.showsID) {
                    guard seen.insert(item.id).inserted else { throw KidsContractError.ambiguousEpisodes }
                    values.append(item)
                }
            }
            start += page.items.count
            if page.items.isEmpty || start >= (page.total ?? start) {
                break
            }
            guard start < 100_000 else { throw KidsAPIError.invalidResponse }
        }
        return values
    }

    public func imageRequest(for item: KidsItem, binding: KidsBinding, width: Int = 600) throws -> URLRequest {
        guard KidsEligibility.permits(item, binding: binding), let tag = item.imageTag,
              let owner = item.imageOwnerID,
              owner == item.id || (item.kind == .episode && owner == item.seriesID) else { throw KidsContractError.denied }
        return request("Items/\(owner)/Images/Primary", query: ["tag": tag, "maxWidth": String(width)])
    }

    private func request(_ path: String, query: [String: String] = [:]) -> URLRequest {
        var components = URLComponents(url: serverURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty {
            components.queryItems = query.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        var request = URLRequest(url: components.url!, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        request.setValue(
            "MediaBrowser Client=\"JellyfinPlayer Kids\", Device=\"Apple TV\", DeviceId=\"kids-catalog\", Version=\"1\", Token=\"\(token)\"",
            forHTTPHeaderField: "Authorization"
        )
        return request
    }

    private func get<T: Decodable>(_ path: String, query: [String: String] = [:]) async throws -> T {
        let endpoint: KidsPerformanceEndpoint = path == "System/Info/Public" ? .serverInfo :
            path == "Users/Me" ? .userPolicy : path.hasSuffix("/Views") ? .libraries :
            path.hasSuffix("/Ancestors") ? .ancestors : path.hasSuffix("/Episodes") ? .episodeList : path == "Items" ? .items : .other
        let trace = KidsPerformance.begin(.http, endpoint: endpoint)
        do {
            let delegate = trace.map(KidsPerformanceTaskDelegate.init(span:))
            let (data, response) = try await session.data(for: request(path, query: query), delegate: delegate)
            guard let http = response as? HTTPURLResponse else { throw KidsAPIError.invalidResponse }
            trace?.mark(.response, values: ["status": Double(http.statusCode), "bytes": Double(data.count)])
            switch http.statusCode {
            case 200 ..< 300: break
            case 401, 403: throw KidsAPIError.authentication
            case 404: throw KidsAPIError.unavailable
            default: throw KidsAPIError.connection
            }
            let decode = KidsPerformance.recorder.begin(.decode, endpoint: endpoint, parent: trace)
            do {
                let result = try JSONDecoder().decode(T.self, from: data)
                decode?.finish(values: ["bytes": Double(data.count)])
                trace?.finish()
                return result
            } catch { decode?.finish(.failure)
                throw KidsAPIError.invalidResponse
            }
        } catch let error as KidsAPIError { trace?.finish(error: error)
            throw error
        } catch is CancellationError { trace?.finish(.cancelled)
            throw CancellationError()
        } catch {
            if Task.isCancelled || (error as? URLError)?.code == .cancelled {
                trace?.finish(.cancelled)
                throw CancellationError()
            }
            trace?.finish(.failure)
            throw KidsAPIError.connection
        }
    }
}
