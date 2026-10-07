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
import SwiftfinMediaCatalog
import SwiftfinNetworking
import Testing

private enum TestFailure: Error { case unavailable }
@MainActor
private final class Gate {
    var continuation: CheckedContinuation<Void, Never>?
    func wait() async {
        await withCheckedContinuation { continuation = $0 }
    }

    func finish() {
        continuation?.resume()
        continuation = nil
    }
}

private struct Captured {
    let path: String
    let method: String
    let query: [String: String]
    let hasBody: Bool
}

@MainActor
private final class Reader: MediaCatalogReading {
    var captured: [Captured] = []
    var responses: [String: Data] = [:]
    var failure = false
    var gatePath: String?
    var gate: Gate?
    func read<Value: Decodable & Sendable>(_ request: Request<Value>) async throws -> Value {
        let values = (request.query ?? []).compactMap { key, value in value.map { (key, $0) } }
        captured.append(Captured(
            path: request.url?.path ?? "",
            method: request.method.rawValue,
            query: Dictionary(grouping: values, by: { $0.0 }).mapValues { $0.map(\.1).joined(separator: ",") },
            hasBody: request.body != nil
        ))
        if let gate, gatePath == nil || gatePath == request.url?.path {
            await gate.wait()
        }
        if failure {
            throw TestFailure.unavailable
        }
        let data = responses[request.url?.path ?? ""] ?? Data((Value.self == [BaseItemDto].self ? "[]" : "{\"Items\":[]}").utf8)
        return try JSONDecoder().decode(Value.self, from: data)
    }
}

@MainActor
private func settle(_ condition: () -> Bool) async {
    for _ in 0 ..< 2000 {
        if condition() {
            return
        }
        await Task.yield()
    }
    #expect(condition())
}

@Suite("Media catalog policies")
struct MediaCatalogPolicyTests {
    @Test(arguments: ["episodes", "seasons", "series", "unknown"])
    func `tv grouping preserves scope`(_ grouping: String) {
        let types = MediaCatalogPolicy.itemTypes(parentType: .collectionFolder, collectionType: .tvshows, groupingID: grouping)
        #expect(types == (grouping == "episodes" ? [.episode] : grouping == "seasons" ? [.season] : [.series]))
        #expect(MediaCatalogPolicy.isRecursive(parentType: .collectionFolder, collectionType: .tvshows, groupingID: grouping) == [
            "episodes",
            "seasons"
        ].contains(grouping))
    }

    @Test
    func `folder and people routing do not broaden parent scope`() {
        let page = CatalogPageRequest(offset: 12, limit: 20)
        let folder = MediaCatalogPolicy.itemParameters(
            .init(parentID: "folder", parentType: .folder, collectionType: .tvshows),
            userID: "user",
            page: page,
            mode: .browse
        )
        #expect(folder.parentID == "folder" && folder.isRecursive == nil)
        #expect(folder.includeItemTypes == [.boxSet, .movie, .musicVideo, .series, .video, .folder, .collectionFolder])
        #expect(folder.startIndex == 12 && folder.limit == 20 && folder.userID == "user")
        let person = MediaCatalogPolicy.itemParameters(
            .init(parentID: "person", parentType: .person, collectionType: nil),
            userID: "user",
            page: page,
            mode: .browse
        )
        let studio = MediaCatalogPolicy.itemParameters(
            .init(parentID: "studio", parentType: .studio, collectionType: nil),
            userID: "user",
            page: page,
            mode: .browse
        )
        #expect(person.personIDs == ["person"] && person.parentID == nil)
        #expect(studio.studioIDs == ["studio"] && studio.parentID == nil)
    }

    @Test
    func `all filter fields and hash letter are preserved`() {
        let filters = CatalogFilters(
            audioLanguages: ["eng"],
            categories: [.movies, .kids],
            genres: ["Comedy"],
            itemTypes: [.episode],
            letter: "#",
            officialRatings: ["G"],
            sortBy: [.dateCreated],
            sortOrder: [.descending],
            subtitleLanguages: ["fra"],
            tags: ["approved"],
            traits: [.isFavorite],
            years: ["2020", "invalid", "2023"],
            query: "fixed"
        )
        let p = MediaCatalogPolicy.itemParameters(
            .init(parentID: "library", parentType: .collectionFolder, collectionType: .movies, filters: filters),
            userID: "u",
            page: .init(offset: 50, limit: 10),
            mode: .browse
        )
        #expect(p.audioLanguages == ["eng"] && p.subtitleLanguages == ["fra"])
        #expect(p.genres == ["Comedy"] && p.tags == ["approved"] && p.officialRatings == ["G"])
        #expect(p.sortBy == [.dateCreated] && p.sortOrder == [.descending] && p.filters == [.isFavorite])
        #expect(p.years == [2020, 2023] && p.includeItemTypes == [.episode])
        #expect(p.isMovie == true && p.isKids == true && p.isSeries == nil && p.isNews == nil && p.isSports == nil)
        #expect(p.nameLessThan == "A" && p.nameStartsWith == nil && p.searchTerm == "fixed")
        #expect(p.fields == [.mediaStreams, .genres, .studios] && p.enableUserData == true)
    }

    @Test
    func `search static override and random are independent from paging`() {
        let q = CatalogItemQuery(
            parentID: "library",
            parentType: .collectionFolder,
            collectionType: .tvshows,
            filters: .init(letter: "B", query: "filter")
        )
        let page = CatalogPageRequest(offset: 50, limit: 100)
        let interactive = MediaCatalogPolicy.itemParameters(q, userID: "u", page: page, mode: .search(query: "input", staticQuery: nil))
        let fixed = MediaCatalogPolicy.itemParameters(q, userID: "u", page: page, mode: .search(query: "input", staticQuery: "static"))
        let random = MediaCatalogPolicy.itemParameters(q, userID: "u", page: page, mode: .random)
        #expect(interactive.searchTerm == "input" && fixed.searchTerm == "static")
        #expect(interactive.nameStartsWith == "B" && interactive.nameLessThan == nil)
        #expect(random.limit == 1 && random.startIndex == nil && random.sortBy == [.random])
        #expect(random.searchTerm == "filter" && random.parentID == "library")
    }

    @Test
    func `normalization counts raw rows and preserves eligibility`() throws {
        let rows = try JSONDecoder().decode(
            [BaseItemDto].self,
            from: Data(
                "[{\"Id\":\"keep\",\"Type\":\"CollectionFolder\",\"CollectionType\":\"movies\"},{\"Id\":\"drop\",\"CollectionType\":\"books\"},{\"Id\":\"nil\",\"Type\":\"Movie\"}]"
                    .utf8
            )
        )
        let p = MediaCatalogPolicy.normalize(rows, parentType: .folder)
        #expect(p.consumedCount == 3 && p.items.map(\.id) == ["keep", "nil"])
        #expect(p.items.first?.type == .folder)
        #expect(MediaCatalogPolicy.normalize(rows, parentType: .collectionFolder).items.first?.type == .collectionFolder)
        #expect(MediaCatalogPolicy.supportedCollectionTypes == [.boxsets, .folders, .homevideos, .movies, .musicvideos, .tvshows, .livetv])
    }

    @Test
    func `view exclusions match exact I ds and nil collection coalesces to folders`() throws {
        let rows = try JSONDecoder().decode(
            [BaseItemDto].self,
            from: Data(
                "[{\"Id\":\"Hide\",\"Type\":\"UserView\"},{\"Id\":\"hide\",\"Type\":\"UserView\"},{\"Type\":\"UserView\"},{\"Id\":\"music\",\"CollectionType\":\"music\"}]"
                    .utf8
            )
        )
        let result = MediaCatalogPolicy.normalizeViews(rows, excludedIDs: ["hide", ""])
        #expect(result.count == 2 && result.first?.id == "Hide" && result.last?.id == nil)
        #expect(result.allSatisfy { $0.type == .folder && $0.collectionType == .folders })
    }

    @Test
    func `scheduled status keeps post padding but rejects ended or failed timers`() {
        let now = Date(timeIntervalSinceReferenceDate: 100)
        #expect(MediaCatalogPolicy.isScheduled(.init(endDate: now.addingTimeInterval(-1), status: .inProgress), now: now))
        #expect(!MediaCatalogPolicy.isScheduled(.init(endDate: now.addingTimeInterval(1), status: .completed), now: now))
        #expect(!MediaCatalogPolicy.isScheduled(.init(status: .cancelled), now: now))
        #expect(!MediaCatalogPolicy.isScheduled(.init(status: .error), now: now))
        #expect(!MediaCatalogPolicy.isScheduled(.init(endDate: now, status: .new), now: now))
        #expect(MediaCatalogPolicy.isScheduled(.init(status: .new), now: now))
    }

    @Test
    func `endpoint capability and bounds are explicit`() {
        #expect(!MediaCatalogQuery.seasons(seriesID: "s", showMissing: true).supportsPagination)
        #expect(!MediaCatalogQuery.latest(parentID: "l").supportsPagination)
        #expect(!MediaCatalogQuery.items(.init(parentID: nil, parentType: nil, collectionType: nil), mode: .random).supportsPagination)
        #expect(MediaCatalogQuery.people(query: nil).supportsPagination)
        #expect(MediaCatalogQuery.recommendedPrograms.supportsPagination)
        #expect(CatalogPageRequest(offset: -1, limit: 0) == CatalogPageRequest(offset: 0, limit: 1))
    }
}

@Suite("Media catalog I/O ownership")
@MainActor
struct MediaCatalogClientTests {
    @Test
    func `transport read port rejects mutation before network access`() async throws {
        let identity = TransportClientIdentity(platform: "test", deviceName: "test", vendorID: UUID().uuidString, version: "1")
        let transport = try JellyfinTransport(url: #require(URL(string: "http://127.0.0.1:1")), identity: identity)
        do { let _: BaseItemDto = try await transport.read(Request(path: "/forbidden", method: .post))
            Issue.record("Mutation passed read-only port")
        } catch MediaCatalogError.nonReadRequest {}
    }

    @Test
    func `all media query variants use read only bodyless requests`() async throws {
        let reader = Reader()
        let client = MediaCatalogClient(reader: reader, userID: "bound")
        let q = CatalogItemQuery(parentID: "library", parentType: .collectionFolder, collectionType: .movies)
        let queries: [MediaCatalogQuery] = [
            .items(q),
            .items(q, mode: .search(query: "search", staticQuery: nil)),
            .items(q, mode: .random),
            .recent,
            .latest(parentID: "library"),
            .nextUp(rewatching: true, maximumAge: 10, now: .now),
            .resume(mediaTypes: [.video]),
            .recordings,
            .programs(category: .kids),
            .recommendedPrograms,
            .people(query: nil),
            .genres,
            .channels,
            .channelSchedule(channelID: "channel", from: .now),
            .seasons(seriesID: "series", showMissing: true),
            .episodes(seasonID: "season", showMissing: true),
            .additionalParts(itemID: "item"),
            .specialFeatures(itemID: "item"),
            .localTrailers(itemID: "item"),
            .similar(itemID: "item", itemType: .movie),
            .scheduledRecordings,
            .artworkSample(parentID: "library", itemTypes: [.movie], favorites: false)
        ]
        for q in queries {
            _ = try await client.page(q, at: .init(offset: 0, limit: 20))
        }
        #expect(reader.captured.count == queries.count)
        #expect(reader.captured.allSatisfy { $0.method == "GET" && !$0.hasBody })
    }

    @Test
    func `already canceled read makes no request`() async throws {
        let reader = Reader()
        let client = MediaCatalogClient(reader: reader, userID: "bound")
        let task = Task { try await client.page(.recent, at: .init(offset: 0, limit: 20)) }
        task.cancel()
        do { _ = try await task.value
            Issue.record("Canceled read was accepted")
        } catch is CancellationError {}
        #expect(reader.captured.isEmpty)
    }

    @Test
    func `people and recommended use real server offsets`() async throws {
        let reader = Reader()
        let client = MediaCatalogClient(reader: reader, userID: "exact-user")
        _ = try await client.page(.people(query: "query"), at: .init(offset: 50, limit: 20))
        _ = try await client.page(.recommendedPrograms, at: .init(offset: 70, limit: 20))
        #expect(reader.captured.map { $0.query["startIndex"] } == ["50", "70"])
        #expect(reader.captured[0].query["searchTerm"] == "query")
        #expect(reader.captured[1].query["userId"] == "exact-user" && reader.captured[1].query["isAiring"] == "true")
    }

    @Test
    func `unpaged endpoints never send A second request`() async throws {
        let reader = Reader()
        reader.responses["/Items/x/LocalTrailers"] = Data("[]".utf8)
        let client = MediaCatalogClient(reader: reader, userID: "u")
        let queries: [MediaCatalogQuery] = [
            .latest(parentID: "l"),
            .seasons(seriesID: "s", showMissing: true),
            .episodes(seasonID: "s", showMissing: true),
            .additionalParts(itemID: "x"),
            .specialFeatures(itemID: "x"),
            .localTrailers(itemID: "x"),
            .similar(itemID: "x", itemType: .movie),
            .scheduledRecordings,
            .artworkSample(parentID: "l", itemTypes: [.movie], favorites: false)
        ]
        for q in queries {
            #expect(try await client.page(q, at: .init(offset: 1, limit: 1)).items.isEmpty)
        }
        #expect(reader.captured.isEmpty)
    }

    @Test
    func `user views uses one exact reader and authenticated user`() async throws {
        let reader = Reader()
        reader
            .responses["/UserViews"] = Data(
                "{\"Items\":[{\"Id\":\"keep\",\"Type\":\"UserView\"},{\"Id\":\"hide\",\"CollectionType\":\"movies\"}]}"
                    .utf8
            )
        reader.responses["/Users/Me"] = Data("{\"Configuration\":{\"MyMediaExcludes\":[\"hide\"]}}".utf8)
        let client = MediaCatalogClient(reader: reader, userID: "bound")
        let result = try await client.userViews()
        #expect(result.map(\.id) == ["keep"])
        #expect(reader.captured.first { $0.path == "/UserViews" }?.query["userId"] == "bound")
        #expect(Set(reader.captured.map(\.path)) == ["/UserViews", "/Users/Me"])
        #expect(reader.captured.allSatisfy { $0.method == "GET" && !$0.hasBody })
    }

    @Test
    func `item filtering preserves consumed rows and random is an exact one item query`() async throws {
        let reader = Reader()
        reader
            .responses["/Items"] = Data("{\"Items\":[{\"Id\":\"a\",\"Type\":\"Movie\"},{\"Id\":\"b\",\"CollectionType\":\"books\"}]}".utf8)
        let client = MediaCatalogClient(reader: reader, userID: "bound")
        let q = CatalogItemQuery(parentID: "approved-library", parentType: .collectionFolder, collectionType: .movies)
        let page = try await client.page(.items(q), at: .init(offset: 7, limit: 2))
        #expect(page.items.map(\.id) == ["a"] && page.consumedCount == 2)
        _ = try await client.page(.items(q, mode: .random), at: .init(offset: 0, limit: 100))
        #expect(reader.captured[0].query["startIndex"] == "7")
        #expect(reader.captured[1].query["limit"] == "1" && reader.captured[1].query["startIndex"] == nil)
        #expect(reader.captured.allSatisfy { $0.query["parentId"] == "approved-library" && $0.query["userId"] == "bound" })
    }

    @Test(arguments: MediaProgramCategory.allCases)
    func `every program category keeps explicit true and false predicates`(_ category: MediaProgramCategory) async throws {
        let reader = Reader()
        let client = MediaCatalogClient(reader: reader, userID: "bound")
        _ = try await client.page(.programs(category: category), at: .init(offset: 9, limit: 10))
        let query = try #require(reader.captured.first).query
        for (name, value) in [
            ("isKids", MediaProgramCategory.kids),
            ("isMovie", .movies),
            ("isNews", .news),
            ("isSeries", .series),
            ("isSports", .sports)
        ] {
            #expect(query[name] == (category == value ? "true" : "false"))
        }
        #expect(query["hasAired"] == "false" && query["startIndex"] == "9" && query["userId"] == "bound")
    }

    @Test
    func `missing season and episode policies and overview are preserved`() async throws {
        let reader = Reader()
        let client = MediaCatalogClient(reader: reader, userID: "bound")
        _ = try await client.page(.seasons(seriesID: "series", showMissing: false), at: .init(offset: 0, limit: 10))
        _ = try await client.page(.episodes(seasonID: "season", showMissing: true), at: .init(offset: 0, limit: 10))
        #expect(reader.captured[0].path == "/Shows/series/Seasons" && reader.captured[0].query["isMissing"] == "false")
        #expect(reader.captured[1].path == "/Shows/season/Episodes" && reader.captured[1].query["seasonId"] == "season")
        #expect(reader.captured[1].query["isMissing"] == nil && reader.captured[1].query["fields"]?.contains("Overview") == true)
        #expect(reader.captured.allSatisfy { $0.query["userId"] == "bound" && $0.query["startIndex"] == nil })
    }

    @Test
    func `artwork sampling is bounded metadata only`() async throws {
        let reader = Reader()
        let client = MediaCatalogClient(reader: reader, userID: "bound")
        _ = try await client.page(
            .artworkSample(parentID: "library", itemTypes: [.movie], favorites: true),
            at: .init(offset: 0, limit: 500)
        )
        let r = try #require(reader.captured.first)
        #expect(r.path == "/Items" && r.method == "GET" && !r.hasBody)
        #expect(r.query["limit"] == "3" && r.query["parentId"] == "library" && r.query["filters"] == "IsFavorite" && r
            .query["sortBy"] == "Random")
        #expect(r.query["fields"] == nil && r.query["userId"] == "bound")
    }

    @Test
    func `scheduled responses filter status and preserve nil last ordering`() async throws {
        let reader = Reader()
        reader
            .responses["/LiveTv/Timers"] = Data(
                "{\"Items\":[{\"Status\":\"New\",\"StartDate\":2,\"EndDate\":200,\"ProgramInfo\":{\"Id\":\"second\"}},{\"Status\":\"InProgress\",\"EndDate\":0,\"ProgramInfo\":{\"Id\":\"nil-last\"}},{\"Status\":\"Cancelled\",\"ProgramInfo\":{\"Id\":\"excluded\"}},{\"Status\":\"New\",\"StartDate\":1,\"EndDate\":200,\"ProgramInfo\":{\"Id\":\"first\"}}]}"
                    .utf8
            )
        let client = MediaCatalogClient(reader: reader, userID: "bound", now: { .init(timeIntervalSinceReferenceDate: 100) })
        let page = try await client.page(.scheduledRecordings, at: .init(offset: 0, limit: 10))
        #expect(page.items.map(\.id) == ["first", "second", "nil-last"] && page.consumedCount == 4)
    }

    @Test
    func `cancellation after non cooperating read drops the result`() async throws {
        let reader = Reader()
        let gate = Gate()
        reader.gate = gate
        let client = MediaCatalogClient(reader: reader, userID: "bound")
        let task = Task { try await client.page(.recent, at: .init(offset: 0, limit: 10)) }
        await settle { gate.continuation != nil }
        task.cancel()
        gate.finish()
        do { _ = try await task.value
            Issue.record("Canceled read returned content")
        } catch is CancellationError {}
    }

    @Test
    func `canceled failure is cancellation and live failure is preserved`() async throws {
        let reader = Reader()
        let gate = Gate()
        reader.gate = gate
        reader.failure = true
        let client = MediaCatalogClient(reader: reader, userID: "bound")
        let task = Task { try await client.page(.recent, at: .init(offset: 0, limit: 10)) }
        await settle { gate.continuation != nil }
        task.cancel()
        gate.finish()
        do { _ = try await task.value
            Issue.record("Canceled failure was accepted")
        } catch is CancellationError {}
        reader.gate = nil
        do { _ = try await client.page(.recent, at: .init(offset: 0, limit: 10))
            Issue.record("Missing transport failure")
        } catch TestFailure.unavailable {}
    }

    @Test
    func `next up cutoff rejects nonfinite age and uses captured time`() async throws {
        let reader = Reader()
        let client = MediaCatalogClient(reader: reader, userID: "bound")
        for age in [Double.infinity, Double.nan, -1, 0, 10] {
            _ = try await client.page(
                .nextUp(rewatching: true, maximumAge: age, now: .init(timeIntervalSince1970: 100)),
                at: .init(offset: 0, limit: 10)
            )
        }
        #expect(reader.captured.dropLast().allSatisfy { $0.query["nextUpDateCutoff"] == nil })
        let value = try #require(reader.captured.last?.query["nextUpDateCutoff"])
        let parser = ISO8601DateFormatter()
        parser.formatOptions = [.withInternetDateTime]
        #expect(parser.date(from: value)?.timeIntervalSince1970 == 90)
    }
}

@MainActor
private final class CatalogBinding { var current = true }

@Suite("Bound content selection")
@MainActor
struct ContentSelectionTests {
    private func client(_ reader: Reader, binding: CatalogBinding? = nil) -> MediaCatalogClient {
        .init(reader: reader, userID: "exact-user", isCurrent: { binding?.current ?? true })
    }

    @Test
    func `next up wins and fetches full episode once`() async throws {
        let reader = Reader()
        reader.responses["/Shows/NextUp"] = Data(#"{"Items":[{"Id":"episode","LocationType":"FileSystem"}]}"#.utf8)
        reader.responses["/Items/episode"] = Data(#"{"Id":"episode","Name":"Full"}"#.utf8)
        let result = try await client(reader).playbackSelection(for: .init(id: "series", type: .series))
        #expect(result?.id == "episode" && result?.name == "Full")
        #expect(reader.captured.map(\.path) == ["/Shows/NextUp", "/Items/episode"])
        #expect(reader.captured[0].query == ["seriesId": "series", "userId": "exact-user"])
        #expect(reader.captured[1].query == ["userId": "exact-user"])
    }

    @Test
    func `missing next up falls back to resume without first query`() async throws {
        let reader = Reader()
        reader.responses["/Shows/NextUp"] = Data(#"{"Items":[{"Id":"missing","LocationType":"Virtual"}]}"#.utf8)
        reader.responses["/UserItems/Resume"] = Data(#"{"Items":[{"Id":"resume"}]}"#.utf8)
        reader.responses["/Items/resume"] = Data(#"{"Id":"resume"}"#.utf8)
        #expect(try await client(reader).playbackSelection(for: .init(id: "series", type: .series))?.id == "resume")
        #expect(reader.captured.map(\.path) == ["/Shows/NextUp", "/UserItems/Resume", "/Items/resume"])
        #expect(reader.captured[1].query == ["parentId": "series", "limit": "1", "userId": "exact-user"])
    }

    @Test
    func `season falls back to first non missing episode and empty selection stops`() async throws {
        let reader = Reader()
        reader.responses["/Items"] = Data(#"{"Items":[{"Id":"first"}]}"#.utf8)
        reader.responses["/Items/first"] = Data(#"{"Id":"first"}"#.utf8)
        #expect(try await client(reader).playbackSelection(for: .init(id: "season", type: .season))?.id == "first")
        #expect(reader.captured.map(\.path) == ["/UserItems/Resume", "/Items", "/Items/first"])
        let q = reader.captured[1].query
        #expect(q["parentId"] == "season" && q["userId"] == "exact-user" && q["isMissing"] == "false" && q["recursive"] == "true")
        #expect(q["sortOrder"] == "Ascending" && q["includeItemTypes"] == "Episode" && q["limit"] == "1")
        let empty = Reader()
        #expect(try await client(empty).playbackSelection(for: .init(id: "series", type: .series)) == nil)
        #expect(empty.captured.map(\.path) == ["/Shows/NextUp", "/UserItems/Resume", "/Items"])
    }

    @Test
    func `absent container identity and direct missing item do no reads`() async throws {
        let reader = Reader()
        let c = client(reader)
        #expect(try await c.playbackSelection(for: .init(type: .series)) == nil)
        #expect(try await c.playbackSelection(for: .init(type: .season)) == nil)
        #expect(try await c.playbackSelection(for: .init(id: "missing", locationType: .virtual, type: .movie)) == nil)
        #expect(try await c.playbackSelection(for: .init(id: "movie", type: .movie))?.id == "movie")
        #expect(reader.captured.isEmpty)
    }

    @Test
    func `home views preserve order and exact exclusions and supported types`() async throws {
        let reader = Reader()
        reader
            .responses["/UserViews"] = Data(
                #"{"Items":[{"Id":"one","CollectionType":"tvshows"},{"Id":"excluded","CollectionType":"movies"},{"Id":"music","CollectionType":"music"},{"Id":"two","CollectionType":"homevideos"},{"Id":"three","CollectionType":"musicvideos"},{"Id":"unknown"}]}"#
                    .utf8
            )
        let result = try await client(reader).homeViews(excludedIDs: ["excluded"])
        #expect(result.map(\.id) == ["one", "two", "three"])
        #expect(reader.captured[0].query == ["userId": "exact-user"])
    }

    @Test
    func `suggestions are bounded metadata and preserve supplied fields`() async throws {
        let reader = Reader()
        _ = try await client(reader).suggestions(fields: [.overview, .primaryImageAspectRatio])
        let q = reader.captured[0].query
        #expect(q["fields"] == "Overview,PrimaryImageAspectRatio" && q["includeItemTypes"] == "Movie,Series")
        #expect(q["recursive"] == "true" && q["limit"] == "10" && q["sortBy"] == "Random" && q["userId"] == "exact-user")
        #expect(reader.captured.allSatisfy { $0.method == "GET" && !$0.hasBody })
    }

    @Test(arguments: [BaseItemKind.person, .boxSet, .musicArtist])
    func `backdrop scope retains person or parent routing`(_ type: BaseItemKind) async throws {
        let reader = Reader()
        _ = try await client(reader).randomBackdrop(for: .init(id: "selected", type: type))
        #expect(reader.captured.count == 1)
        let q = reader.captured[0].query
        #expect(q["userId"] == "exact-user" && q["limit"] == "1" && q["sortBy"] == "Random")
        #expect(q["personIds"] == (type == .person ? "selected" : nil))
        #expect(q["parentId"] == (type == .person ? nil : "selected"))
    }

    @Test
    func `backdrop unsupported and empty guide or adjacent identity do no IO`() async throws {
        let reader = Reader()
        let c = client(reader)
        #expect(try await c.randomBackdrop(for: .init(id: "movie", type: .movie)) == nil)
        #expect(try await c.programs(channelIDs: [], startDate: .distantPast, endDate: .distantFuture).isEmpty)
        let adjacent = try await c.adjacentEpisodes(for: .init(seriesID: "series", type: .episode))
        #expect(adjacent.next == nil && adjacent.previous == nil && reader.captured.isEmpty)
    }

    @Test
    func `adjacent responses find current identity rather than assuming center`() {
        let a = BaseItemDto(id: "a"), b = BaseItemDto(id: "b"), c = BaseItemDto(id: "c")
        let only = AdjacentEpisodes.resolve([b], currentID: "b")
        #expect(only.previous == nil && only.next == nil)
        let left = AdjacentEpisodes.resolve([b, c], currentID: "b")
        #expect(left.previous == nil && left.next?.id == "c")
        let right = AdjacentEpisodes.resolve([a, b], currentID: "b")
        #expect(right.previous?.id == "a" && right.next == nil)
        let middle = AdjacentEpisodes.resolve([a, b, c], currentID: "b")
        #expect(middle.previous?.id == "a" && middle.next?.id == "c")
        let first = AdjacentEpisodes.resolve([a, b, c], currentID: "a")
        #expect(first.previous == nil && first.next?.id == "b")
        let absent = AdjacentEpisodes.resolve([a, c], currentID: "b")
        #expect(absent.previous == nil && absent.next == nil)
    }

    @Test
    func `adjacent and trailers keep exact user series and item`() async throws {
        let reader = Reader()
        let c = client(reader)
        _ = try await c.adjacentEpisodes(for: .init(id: "episode", seriesID: "series", type: .episode))
        _ = try await c.localTrailers(itemID: "movie")
        #expect(reader.captured[0].path == "/Shows/series/Episodes" && reader.captured[0].query == [
            "userId": "exact-user",
            "adjacentTo": "episode",
            "limit": "3"
        ])
        #expect(reader.captured[1].path == "/Items/movie/LocalTrailers" && reader.captured[1].query == ["userId": "exact-user"])
    }

    @Test
    func `guide window retains finite channels dates and disabled payload fields`() async throws {
        let reader = Reader()
        _ = try await client(reader).programs(
            channelIDs: ["one", "two"],
            startDate: Date(timeIntervalSince1970: 0),
            endDate: Date(timeIntervalSince1970: 3600)
        )
        let q = reader.captured[0].query
        #expect(reader.captured[0].path == "/LiveTv/Programs")
        #expect(q["channelIds"] == "one,two" && q["userId"] == "exact-user" && q["sortBy"] == "StartDate")
        #expect(q["minEndDate"] == "1970-01-01T00:00:00Z" && q["maxStartDate"] == "1970-01-01T01:00:00Z")
        #expect(q["enableImages"] == "false" && q["enableUserData"] == "false" && q["enableTotalRecordCount"] == "false")
    }

    @Test
    func `replaced binding cannot continue selection or publish late failure`() async {
        for failure in [false, true] {
            let reader = Reader()
            let binding = CatalogBinding()
            let gate = Gate()
            reader.gate = gate
            reader.failure = failure
            let c = client(reader, binding: binding)
            let task = Task { try await c.playbackSelection(for: .init(id: "series", type: .series)) }
            await settle { gate.continuation != nil }
            binding.current = false
            gate.finish()
            await #expect(throws: CancellationError.self) { try await task.value }
            #expect(reader.captured.count == 1)
        }
    }

    @Test
    func `binding expires between returned value and publication`() async throws {
        let reader = Reader()
        let binding = CatalogBinding()
        let c = client(reader, binding: binding)
        _ = try await c.suggestions(fields: [])
        binding.current = false
        #expect(throws: CancellationError.self) { try c.checkBinding() }
        await #expect(throws: CancellationError.self) { try await c.homeViews(excludedIDs: []) }
        #expect(reader.captured.count == 1)
    }
}
