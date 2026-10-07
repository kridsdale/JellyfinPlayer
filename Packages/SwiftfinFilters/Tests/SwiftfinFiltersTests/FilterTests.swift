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
import SwiftfinFilters
import SwiftfinNetworking
import Testing

@Suite("Saved filter schema and precedence")
struct FilterSelectionTests {
    private var populated: ItemFilterCollection {
        .init(
            audioLanguages: [.init(displayTitle: "Français", value: "fra")],
            categories: [.kids],
            genres: ["Comedy"],
            itemTypes: [.series],
            letter: ["A", "B"],
            officialRatings: ["TV-Y"],
            sortBy: [.dateCreated],
            sortOrder: [.descending],
            subtitleLanguages: [.init(displayTitle: "日本語", value: "jpn")],
            tags: ["Approved"],
            traits: [.isFavorite],
            years: [2024],
            query: "title"
        )
    }

    @Test
    func `installed schema round trips all fields without losing labels or letters`() throws {
        let fixture = Data(
            #"{"audioLanguages":[{"displayTitle":"Français","value":"fra"}],"categories":["kids"],"genres":[{"value":"Comedy"}],"itemTypes":["Series"],"letter":[{"value":"A"},{"value":"B"}],"officialRatings":[{"value":"TV-Y"}],"sortBy":["DateCreated"],"sortOrder":["Descending"],"subtitleLanguages":[{"displayTitle":"日本語","value":"jpn"}],"tags":[{"value":"Approved"}],"traits":["IsFavorite"],"years":[{"value":"2024"}],"query":"title"}"#
                .utf8
        )
        let decoded = try JSONDecoder().decode(ItemFilterCollection.self, from: fixture)
        #expect(decoded == populated)
        let encoded = try JSONEncoder().encode(decoded)
        let original = try #require(JSONSerialization.jsonObject(with: fixture) as? NSDictionary)
        let result = try #require(JSONSerialization.jsonObject(with: encoded) as? NSDictionary)
        #expect(original == result)
        #expect(decoded.letter.map(\.value) == ["A", "B"])
        #expect(decoded.audioLanguages.first?.displayTitle == "Français")
        #expect(decoded.catalogSnapshot.letter == "A")
        #expect(decoded.catalogSnapshot.audioLanguages == ["fra"])
        #expect(decoded.catalogSnapshot.categories.map(\.rawValue) == ["kids"])
        #expect(decoded.catalogSnapshot.traits == [.isFavorite])
    }

    @Test
    func `default encoding preserves keys and omitted nil query`() throws {
        let data = try JSONEncoder().encode(ItemFilterCollection.default)
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(Set(object.keys) == Set([
            "audioLanguages",
            "categories",
            "genres",
            "itemTypes",
            "letter",
            "officialRatings",
            "sortBy",
            "sortOrder",
            "subtitleLanguages",
            "tags",
            "traits",
            "years"
        ]))
        #expect(object["sortBy"] as? [String] == ["SortName"])
        #expect(object["sortOrder"] as? [String] == ["Ascending"])
        #expect(try JSONDecoder().decode(ItemFilterCollection.self, from: data) == .default)
    }

    @Test
    func `sort only is changed but not queryable and whitespace query is preserved`() {
        let sort = ItemFilterCollection(sortBy: [.random])
        #expect(sort.isNotEmpty && !sort.hasQueryableFilters && sort.containsFilters(ofType: .sortBy))
        #expect(!ItemFilterCollection(query: "").hasQueryableFilters)
        #expect(ItemFilterCollection(query: " ").hasQueryableFilters)
        #expect(ItemFilterCollection.favorites.traits == [.isFavorite])
        #expect(ItemFilterCollection.recent.sortBy == [.dateCreated] && ItemFilterCollection.recent.sortOrder == [.descending])
    }

    @Test
    func `union preserves whole fields and treats sort as one selection`() {
        let mine = ItemFilterCollection(genres: ["Mine", "Mine"], letter: ["X", "Y"], sortOrder: [.descending], query: "")
        let other = populated
        let union = mine.union(other)
        #expect(union.genres == ["Mine", "Mine"] && union.letter == ["X", "Y"])
        #expect(union.audioLanguages == other.audioLanguages && union.tags == other.tags)
        #expect(union.sortBy == [.sortName] && union.sortOrder == [.descending])
        #expect(union.query == "")
        #expect(ItemFilterCollection.default.union(other) == other)
        #expect(other.union(.default) == other)
    }

    @Test(arguments: ItemFilterType.allCases)
    func `resetting one type preserves unrelated values`(_ type: ItemFilterType) {
        var value = populated
        #expect(value.containsFilters(ofType: type))
        value.reset(type)
        #expect(!value.containsFilters(ofType: type))
        for untouched in ItemFilterType.allCases where untouched != type {
            #expect(value.containsFilters(ofType: untouched))
        }
        #expect(value.query == "title" && value.itemTypes == [.series])
        var reset = value
        reset.reset(nil)
        #expect(reset == .default)
    }

    @Test
    func `language construction requires both fields and conversions preserve values`() {
        #expect(ItemLanguage(.init(name: "Name", value: "code")) == .init(displayTitle: "Name", value: "code"))
        #expect(ItemLanguage(.init(name: "Name")) == nil && ItemLanguage(.init(value: "code")) == nil)
        let erased = AnyItemFilter(displayTitle: "Localized", value: "value")
        #expect(ItemLanguage(from: erased).displayTitle == "Localized")
        #expect(ItemGenre(from: erased).value == "value" && ItemLetter(from: erased).displayTitle == "value")
        #expect(AnyItemFilter(from: erased) == erased)
        #expect(ItemYear(integerLiteral: 2024).intValue == 2024)
        #expect(ChannelCategory.allCases.map(\.rawValue) == ["movies", "series", "news", "kids", "sports"])
        #expect(ItemFilterType.allCases.map(\.rawValue) == [
            "audioLanguage",
            "genres",
            "letter",
            "officialRatings",
            "sortBy",
            "subtitleLanguage",
            "tags",
            "traits",
            "years",
            "category"
        ])
    }
}

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

private enum StubError: Error { case offline }
@MainActor
private final class Binding { var current = true }
private struct Call { let path: String
    let query: [String: String]
}

@MainActor
private final class Sender: JellyfinRequestSending {
    var calls: [Call] = []
    var responses: [String: Data] = [:]
    var gate: Gate?
    var fail = false
    func value<Value: Decodable & Sendable>(for request: Request<Value>) async throws -> Value {
        let path = request.url?.path ?? ""
        let query = Dictionary(grouping: (request.query ?? []).compactMap { k, v in v.map { (k, $0) } }, by: { $0.0 })
            .mapValues { $0.map(\.1).joined(separator: ",") }
        calls.append(.init(path: path, query: query))
        if let gate {
            await gate.wait()
        }
        if fail {
            throw StubError.offline
        }
        return try JSONDecoder().decode(Value.self, from: responses[path] ?? Data("{}".utf8))
    }

    func complete(_ request: Request<Void>) async throws {
        Issue.record("Filter discovery cannot send commands")
    }
}

@MainActor
private func settle(_ predicate: () -> Bool) async {
    for _ in 0 ..< 2000 {
        if predicate() {
            return
        }
        await Task.yield()
    }
    #expect(predicate())
}

@Suite("Bound filter discovery")
@MainActor
struct FilterDiscoveryTests {
    private func client(_ sender: Sender, binding: Binding? = nil) -> QueryFiltersClient {
        QueryFiltersClient(executor: .init(sender: sender, isCurrent: { binding?.current ?? true }), userID: "captured-user")
    }

    @Test
    func `modern and legacy routes capture user scope and normalize only their fields`() async throws {
        let sender = Sender()
        sender
            .responses["/Items/Filters2"] = Data(
                #"{"AudioLanguages":[{"Name":"Zulu","Value":"z"},{"Name":"Alpha","Value":"a"},{"Name":"Invalid"}],"Genres":[{"Name":"Comedy"},{}],"SubtitleLanguages":[{"Name":"Zulu","Value":"z"},{"Name":"Alpha","Value":"a"}],"Tags":["B","A","B"]}"#
                    .utf8
            )
        sender.responses["/Items/Filters"] = Data(#"{"OfficialRatings":["TV-Y","G"],"Years":[2020,2024,2020]}"#.utf8)
        let filters = client(sender)
        let modern = try await filters.modern(parentID: "parent", itemTypes: [.series, .movie])
        #expect(modern.audioLanguages.map(\.displayTitle) == ["Alpha", "Zulu"])
        #expect(modern.subtitleLanguages.map(\.value) == ["a", "z"])
        #expect(modern.genres.map(\.value) == ["Comedy"] && modern.tags.map(\.value) == ["B", "A", "B"])
        let original = ItemFilterCollection(
            categories: [.kids],
            letter: ["X", "Y"],
            officialRatings: ["Original"],
            years: [1999],
            query: "query"
        )
        let first = modern.applying(to: original)
        #expect(first.officialRatings == original.officialRatings && first.years == original.years)
        #expect(first.letter == original.letter && first.query == "query")
        let legacy = try await filters.legacy(parentID: "parent", itemTypes: [.series, .movie])
        #expect(legacy.years.map(\.value) == ["2024", "2020", "2020"])
        #expect(legacy.officialRatings.map(\.value) == ["TV-Y", "G"])
        let second = legacy.applying(to: first)
        #expect(second.audioLanguages == first.audioLanguages && second.tags == first.tags && second.categories == [.kids])
        #expect(sender.calls.map(\.path) == ["/Items/Filters2", "/Items/Filters"])
        for call in sender.calls {
            #expect(call.query["userId"] == "captured-user" && call.query["parentId"] == "parent")
            #expect(call.query["includeItemTypes"] == "Series,Movie")
        }
        #expect(sender.calls[0].query["recursive"] == "true")
        #expect(sender.calls[1].query["recursive"] == nil)
    }

    @Test
    func `nil scope and empty responses stay empty and preserve static values`() async throws {
        let sender = Sender()
        let filters = client(sender)
        let modern = try await filters.modern(parentID: nil, itemTypes: [])
        let legacy = try await filters.legacy(parentID: nil, itemTypes: [])
        let value = legacy.applying(to: modern.applying(to: .init(categories: [.movies], letter: ["#"])))
        #expect(value.audioLanguages.isEmpty && value.tags.isEmpty && value.years.isEmpty)
        #expect(value.categories == [.movies] && value.letter == ["#"])
        #expect(sender.calls.allSatisfy { $0.query["parentId"] == nil })
    }

    @Test
    func `binding change between stages cannot use A new account or send legacy`() async throws {
        let sender = Sender()
        let binding = Binding()
        let filters = client(sender, binding: binding)
        _ = try await filters.modern(parentID: "parent", itemTypes: [.series])
        binding.current = false
        do { _ = try await filters.legacy(parentID: "parent", itemTypes: [.series])
            Issue.record("Expired binding accepted")
        } catch { #expect(error is CancellationError) }
        #expect(sender.calls.count == 1)
    }

    @Test(arguments: [false, true])
    func `expired returned values cannot pass publication gate`(_ useLegacy: Bool) async throws {
        let sender = Sender()
        let binding = Binding()
        let filters = client(sender, binding: binding)
        if useLegacy {
            _ = try await filters.legacy(parentID: nil, itemTypes: [])
        } else {
            _ = try await filters.modern(parentID: nil, itemTypes: [])
        }
        binding.current = false
        do { try filters.checkBinding()
            Issue.record("Expired values accepted for publication")
        } catch { #expect(error is CancellationError) }
        #expect(sender.calls.count == 1)
    }

    @Test(arguments: [false, true])
    func `obsolete success and error cannot return discovery`(_ fail: Bool) async {
        let sender = Sender()
        let gate = Gate()
        let binding = Binding()
        sender.gate = gate
        sender.fail = fail
        let filters = client(sender, binding: binding)
        let task = Task { try await filters.modern(parentID: "parent", itemTypes: [.movie]) }
        await settle { gate.continuation != nil }
        binding.current = false
        gate.finish()
        do { _ = try await task.value
            Issue.record("Obsolete discovery returned")
        } catch { #expect(error is CancellationError) }
        #expect(sender.calls.count == 1)
    }

    @Test
    func `canceled wait cannot publish and valid transport errors are preserved`() async {
        let sender = Sender()
        let gate = Gate()
        sender.gate = gate
        let filters = client(sender)
        let task = Task { try await filters.legacy(parentID: nil, itemTypes: []) }
        await settle { gate.continuation != nil }
        task.cancel()
        gate.finish()
        do { _ = try await task.value
            Issue.record("Canceled discovery returned")
        } catch { #expect(error is CancellationError) }
        sender.gate = nil
        sender.fail = true
        do { _ = try await filters.legacy(parentID: nil, itemTypes: [])
            Issue.record("Transport error lost")
        } catch { #expect(error is StubError) }
    }
}
