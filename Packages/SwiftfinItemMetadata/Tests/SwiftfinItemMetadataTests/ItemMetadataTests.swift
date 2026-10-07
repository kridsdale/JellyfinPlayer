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
import Testing

private enum StubError: Error { case offline }
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

@MainActor
private final class Binding { var current = true }
private struct Captured {
    let path: String
    let method: String
    let query: [String: String]
    let body: Data?
    let headers: [String: String]
    let rawData: Data?
}

@MainActor
private final class Sender: JellyfinRequestSending {
    var calls: [Captured] = []
    var responses: [String: Data] = [:]
    var gate: Gate?
    var failure = false
    var failingPath: String?
    private func capture(_ request: Request<some Any>) throws {
        let pairs = (request.query ?? []).compactMap { k, v in v.map { (k, $0) } }
        try calls.append(.init(
            path: request.url?.path ?? "",
            method: request.method.rawValue,
            query: Dictionary(grouping: pairs, by: { $0.0 }).mapValues { $0.map(\.1).joined(separator: ",") },
            body: request.body.map { try JSONEncoder().encode($0) },
            headers: request.headers ?? [:],
            rawData: request.body as? Data
        ))
    }

    func value<Value: Decodable & Sendable>(for request: Request<Value>) async throws -> Value {
        try capture(request)
        if let gate {
            await gate.wait()
        }
        if failure || request.url?.path == failingPath {
            throw StubError.offline
        }
        let data = responses[request.url?.path ?? ""] ?? Data((String(describing: Value.self).hasPrefix("Array<") ? "[]" : "{}").utf8)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(Value.self, from: data)
    }

    func complete(_ request: Request<Void>) async throws {
        try capture(request)
        if let gate {
            await gate.wait()
        }
        if failure || request.url?.path == failingPath {
            throw StubError.offline
        }
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

import SwiftfinItemMetadata

@Suite("Item metadata editing policies")
struct MetadataPolicyTests {
    @Test
    func `removing from missing fields preserves nil and append keeps duplicates`() {
        let original = BaseItemDto(id: "same", name: "Title", overview: "Description")
        #expect(ItemMetadataPolicy.genres(.remove(["A"]), in: original).genres == nil)
        #expect(ItemMetadataPolicy.tags(.remove(["A"]), in: original).tags == nil)
        #expect(ItemMetadataPolicy.studios(.remove([.init(id: "x")]), in: original).studios == nil)
        #expect(ItemMetadataPolicy.people(.remove([.init(id: "x")]), in: original).people == nil)
        let changed = ItemMetadataPolicy.genres(.append(["A", "A"]), in: original)
        #expect(changed.genres == ["A", "A"] && changed.id == "same" && changed.overview == "Description" && original.genres == nil)
    }

    @Test
    func `removal and reordering affect only selected field`() {
        let item = BaseItemDto(
            genres: ["B", "A", "B"],
            id: "item",
            people: [.init(id: "person")],
            studios: [.init(id: "studio")],
            tags: ["T"]
        )
        #expect(ItemMetadataPolicy.genres(.remove(["B"]), in: item).genres == ["A"])
        #expect(ItemMetadataPolicy.genres(.replace([]), in: item).genres == [])
        #expect(ItemMetadataPolicy.tags(.append(["New"]), in: item).tags == ["T", "New"])
        #expect(ItemMetadataPolicy.studios(.remove([.init(id: "studio")]), in: item).studios == [])
        #expect(ItemMetadataPolicy.people(.replace([.init(id: "new")]), in: item).people?.first?.id == "new")
        #expect(ItemMetadataPolicy.tags(.replace(["X"]), in: item).genres == item.genres)
    }

    @Test(arguments: [PersonKind.unknown, .actor, .director])
    func `person role fallback preserves unknown`(_ kind: PersonKind) {
        let person = ItemMetadataPolicy.person(id: "id", name: "Name", kind: kind, role: "")
        #expect(person.role == (kind == .unknown ? nil : kind.rawValue))
        #expect(ItemMetadataPolicy.person(id: nil, name: "Name", kind: kind, role: "Custom").role == "Custom")
    }

    @Test
    func `query presence and case insensitive names match old editing rules`() {
        #expect(MetadataSearchQuery(name: "", originalTitle: "").isEmpty)
        #expect(MetadataSearchQuery(year: 2000).isNotEmpty && MetadataSearchQuery(originalTitle: "Original").isNotEmpty)
        #expect(ItemMetadataPolicy.nameMatches("alpha", names: ["Alpha", "Beta"]))
        #expect(!ItemMetadataPolicy.nameMatches("alp", names: ["Alpha"]))
    }

    @Test
    func `subtitle classification excludes non subtitle and unclassified streams`() {
        let item = BaseItemDto(mediaSources: [.init(mediaStreams: [
            .init(index: 1, isExternal: false, type: .subtitle),
            .init(index: 2, isExternal: true, type: .subtitle),
            .init(index: 3, type: .subtitle),
            .init(index: 4, isExternal: true, type: .audio)
        ])])
        let groups = ItemMetadataPolicy.subtitles(item)
        #expect(groups.internalStreams.map(\.index) == [1] && groups.externalStreams.map(\.index) == [2])
    }

    @Test
    func `update payload strips trickplay only`() {
        let item = BaseItemDto(id: "item", name: "Name", tags: ["Tag"], trickplay: [:])
        let payload = ItemMetadataPolicy.updatePayload(item)
        #expect(payload.trickplay == nil && payload.id == item.id && payload.name == item.name && payload.tags == item.tags && item
            .trickplay != nil)
    }
}

@Suite("Item metadata exact requests")
@MainActor
struct MetadataRequestTests {
    private func client(_ sender: Sender, binding: Binding? = nil, user: String = "user") -> ItemMetadataClient {
        .init(
            executor: .init(sender: sender, isCurrent: { binding?.current ?? true }),
            userID: user,
            bindingID: .init(transport: ObjectIdentifier(sender), userID: user)
        )
    }

    @Test
    func `reference and image reads preserve scope and pagination`() async throws {
        let s = Sender()
        let c = client(s)
        _ = try await c.countries()
        _ = try await c.cultures()
        _ = try await c.parentalRatings()
        _ = try await c.imageProviders(itemID: "item")
        _ = try await c.remoteImages(itemID: "item", type: .primary, includeAllLanguages: true, provider: "Provider", offset: 20, limit: 10)
        #expect(s.calls.allSatisfy { $0.method == "GET" && $0.body == nil })
        let last = try #require(s.calls.last)
        #expect(last.path == "/Items/item/RemoteImages" && last.query["startIndex"] == "20" && last.query["limit"] == "10" && last
            .query["providerName"] == "Provider" && last.query["includeAllLanguages"] == "true" && last.query["type"] == "Primary")
    }

    @Test(arguments: [
        BaseItemKind.boxSet,
        .movie,
        .person,
        .series
    ])
    func `identity queries preserve every field`(_ kind: BaseItemKind) async throws {
        let s = Sender()
        let c = client(s)
        _ = try await c.identityResults(itemID: "item", itemType: kind, query: .init(name: "Name", originalTitle: "Original", year: 2001))
        let call = try #require(s.calls.first)
        let body = try #require(call.body)
        let object = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        let info = try #require(object["SearchInfo"] as? [String: Any])
        #expect(call.method == "POST" && object["ItemId"] as? String == "item")
        #expect(info["Name"] as? String == "Name" && info["OriginalTitle"] as? String == "Original" && info["Year"] as? Int == 2001)
    }

    @Test
    func `empty or unsupported identity queries do no IO`() async throws {
        let s = Sender()
        let c = client(s)
        #expect(try await c.identityResults(itemID: "item", itemType: .movie, query: .init()).isEmpty)
        #expect(try await c.identityResults(itemID: "item", itemType: .audio, query: .init(name: "Name")).isEmpty)
        #expect(s.calls.isEmpty)
    }

    @Test
    func `item reads and component search retain user and SDK mappings`() async throws {
        let s = Sender()
        let c = client(s)
        s.responses["/Genres"] = Data(#"{"Items":[{"Name":"Genre"},{}]}"#.utf8)
        s.responses["/Studios"] = Data(#"{"Items":[{"Id":"studio","Name":"Studio"}]}"#.utf8)
        s.responses["/Persons"] = Data(#"{"Items":[{"Id":"person","Name":"Person"}]}"#.utf8)
        s.responses["/Items/Filters"] = Data(#"{"Tags":["Tag"]}"#.utf8)
        _ = try await c.item(id: "item")
        #expect(try await c.genreMatches(query: "") == ["Genre"])
        #expect(try await c.studioMatches(query: "Studio").first?.id == "studio")
        #expect(try await c.peopleMatches(query: "Person").first?.name == "Person")
        #expect(try await c.tags() == ["Tag"])
        #expect(s.calls[0].query["userId"] == "user" && s.calls.last?.query["userId"] == "user")
        #expect(s.calls[1].query["searchTerm"] == nil && s.calls[2].query["searchTerm"] == "Studio")
    }

    @Test
    func `update refresh identity and delete use only synthetic command port`() async throws {
        let s = Sender()
        let c = client(s)
        try await c.update(itemID: "item", item: .init(id: "item", tags: ["Tag"], trickplay: [:]))
        try await c.refresh(
            itemID: "item",
            options: .init(
                metadataMode: .fullRefresh,
                imageMode: .validationOnly,
                replaceMetadata: true,
                replaceImages: false,
                regenerateTrickplay: true
            )
        )
        try await c.applyIdentity(itemID: "item", result: .init(name: "Result"))
        try await c.deleteItem(id: "item")
        #expect(s.calls.count == 4)
        let object = try JSONSerialization.jsonObject(with: #require(s.calls[0].body)) as? [String: Any]
        #expect(object?["Trickplay"] == nil && object?["Tags"] as? [String] == ["Tag"])
        #expect(s.calls[1].query["replaceAllMetadata"] == "true" && s.calls[1].query["replaceAllImages"] == "false" && s.calls[1]
            .query["regenerateTrickplay"] == "true")
        #expect(s.calls[3].method == "DELETE" && s.calls[3].path == "/Items/item")
    }

    @Test
    func `subtitle upload encodes exact bytes and flags`() async throws {
        let s = Sender()
        let c = client(s)
        try await c.uploadSubtitle(
            itemID: "item",
            data: Data([0, 255, 17]),
            format: "srt",
            language: "eng",
            forced: true,
            hearingImpaired: false
        )
        let body = try #require(s.calls.first?.body)
        let object = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(object["Data"] as? String == Data([0, 255, 17])
            .base64EncodedString() && object["Format"] as? String == "srt" && object["Language"] as? String == "eng")
        #expect(object["IsForced"] as? Bool == true && object["IsHearingImpaired"] as? Bool == false)
    }

    @Test
    func `subtitle search none and download batch are bound to exact item`() async throws {
        let s = Sender()
        let c = client(s)
        #expect(try await c.searchSubtitles(itemID: "item", language: "", perfectMatch: false).isEmpty)
        #expect(s.calls.isEmpty)
        _ = try await c.searchSubtitles(itemID: "item", language: "eng", perfectMatch: true)
        try await c.downloadSubtitles(itemID: "item", subtitleIDs: ["a", "b"])
        #expect(s.calls.count == 3 && s.calls.allSatisfy { $0.path.contains("item") })
        #expect(s.calls[0].query["isPerfectMatch"] == "true")
    }

    @Test
    func `subtitle deletion descends and stops at failed index`() async throws {
        let s = Sender()
        let c = client(s)
        try await c.deleteSubtitles(itemID: "item", indices: [2, 7, 1])
        #expect(s.calls.map(\.path) == ["/Videos/item/Subtitles/7", "/Videos/item/Subtitles/2", "/Videos/item/Subtitles/1"])
        s.calls = []
        s.failingPath = "/Videos/item/Subtitles/2"
        do { try await c.deleteSubtitles(itemID: "item", indices: [7, 2, 1])
            Issue.record("Expected failed deletion")
        } catch let error as MetadataSubtitleDeletionFailure { #expect(error.index == 2 && error.underlying is StubError) }
        #expect(s.calls.map(\.path) == ["/Videos/item/Subtitles/7", "/Videos/item/Subtitles/2"])
    }

    @Test
    func `replaced binding rejects metadata and commands before IO`() async {
        let s = Sender()
        let b = Binding()
        b.current = false
        let c = client(s, binding: b)
        await #expect(throws: CancellationError.self) { try await c.item(id: "item") }
        await #expect(throws: CancellationError.self) { try await c.deleteItem(id: "item") }
        await #expect(throws: CancellationError.self) { try await c.identityResults(itemID: "item", itemType: .movie, query: .init()) }
        #expect(s.calls.isEmpty)
    }
}

@Suite("Metadata tag binding and shared loads")
@MainActor
struct MetadataTagTests {
    private func client(_ s: Sender, user: String = "user") -> ItemMetadataClient {
        .init(
            executor: .init(sender: s),
            userID: user,
            bindingID: .init(transport: ObjectIdentifier(s), userID: user)
        )
    }

    @Test
    func `shared loads and cached empty results do not repeat IO`() async throws {
        let s = Sender()
        let gate = Gate()
        s.gate = gate
        s.responses["/Items/Filters"] = Data(#"{"Tags":["Alpha","Beta"]}"#.utf8)
        let store = MetadataTagSearchStore()
        let c = client(s)
        let first = Task { try await store.search(prefix: "a", client: c) }
        await settle { gate.continuation != nil }
        var secondStarted = false
        let second = Task { secondStarted = true
            return try await store.search(prefix: "b", client: c)
        }
        await settle { secondStarted }
        #expect(s.calls.count == 1)
        gate.finish()
        #expect(try await first.value == ["Alpha"])
        #expect(try await second.value == ["Beta"])
        #expect(s.calls.count == 1)
        let empty = Sender()
        let e = client(empty)
        let other = MetadataTagSearchStore()
        #expect(try await other.search(prefix: "a", client: e).isEmpty)
        #expect(try await other.search(prefix: "b", client: e).isEmpty)
        #expect(empty.calls.count == 1)
    }

    @Test
    func `add before load does not suppress full catalog load`() async throws {
        let s = Sender()
        s.responses["/Items/Filters"] = Data(#"{"Tags":["Alpha","Beta"]}"#.utf8)
        let store = MetadataTagSearchStore()
        let c = client(s)
        try store.add(["Added"], client: c)
        #expect(try await store.search(prefix: "a", client: c) == ["Added", "Alpha"])
        #expect(s.calls.count == 1)
    }

    @Test
    func `account and transport changes cannot reuse previous tags`() async throws {
        let a = Sender()
        a.responses["/Items/Filters"] = Data(#"{"Tags":["Alpha"]}"#.utf8)
        let b = Sender()
        b.responses["/Items/Filters"] = Data(#"{"Tags":["Beta"]}"#.utf8)
        let store = MetadataTagSearchStore()
        let ca = client(a)
        let cb = client(b)
        #expect(try await store.search(prefix: "a", client: ca) == ["Alpha"])
        #expect(try await store.search(prefix: "a", client: cb).isEmpty)
        #expect(try await store.search(prefix: "b", client: cb) == ["Beta"])
        a.responses["/Items/Filters"] = Data(#"{"Tags":["AnotherUser"]}"#.utf8)
        #expect(try await store.search(prefix: "a", client: client(a, user: "second-user")) == ["AnotherUser"])
        #expect(a.calls.count == 2 && b.calls.count == 1)
    }

    @Test(arguments: [false, true])
    func `replacement rejects late load and late error`(_ failure: Bool) async throws {
        let a = Sender()
        let gate = Gate()
        a.gate = gate
        a.failure = failure
        a.responses["/Items/Filters"] = Data(#"{"Tags":["Alpha"]}"#.utf8)
        let b = Sender()
        b.responses["/Items/Filters"] = Data(#"{"Tags":["Beta"]}"#.utf8)
        let store = MetadataTagSearchStore()
        let ca = client(a)
        let cb = client(b)
        let old = Task { try await store.search(prefix: "a", client: ca) }
        await settle { gate.continuation != nil }
        #expect(try await store.search(prefix: "b", client: cb) == ["Beta"])
        gate.finish()
        await #expect(throws: CancellationError.self) { try await old.value }
        #expect(try await store.search(prefix: "b", client: cb) == ["Beta"] && b.calls.count == 1)
    }

    @Test
    func `canceled waiter does not cancel another shared waiter`() async throws {
        let s = Sender()
        let gate = Gate()
        s.gate = gate
        s.responses["/Items/Filters"] = Data(#"{"Tags":["Alpha"]}"#.utf8)
        let store = MetadataTagSearchStore()
        let c = client(s)
        let first = Task { try await store.search(prefix: "a", client: c) }
        await settle { gate.continuation != nil }
        var secondStarted = false
        let second = Task { secondStarted = true
            return try await store.search(prefix: "a", client: c)
        }
        await settle { secondStarted }
        #expect(s.calls.count == 1)
        first.cancel()
        gate.finish()
        await #expect(throws: CancellationError.self) { try await first.value }
        #expect(try await second.value == ["Alpha"] && s.calls.count == 1)
    }

    @Test
    func `failed load can retry and invalidation refetches`() async throws {
        let s = Sender()
        s.failure = true
        let store = MetadataTagSearchStore()
        let c = client(s)
        await #expect(throws: StubError.self) { try await store.search(prefix: "a", client: c) }
        s.failure = false
        s.responses["/Items/Filters"] = Data(#"{"Tags":["Alpha"]}"#.utf8)
        #expect(try await store.search(prefix: "a", client: c) == ["Alpha"])
        store.invalidate()
        #expect(try await store.search(prefix: "a", client: c) == ["Alpha"])
        #expect(s.calls.count == 3)
    }

    @Test
    func `returning to same binding cannot publish first generation`() async throws {
        let a = Sender()
        let gate = Gate()
        a.gate = gate
        a.responses["/Items/Filters"] = Data(#"{"Tags":["Alpha"]}"#.utf8)
        let b = Sender()
        b.responses["/Items/Filters"] = Data(#"{"Tags":["Beta"]}"#.utf8)
        let store = MetadataTagSearchStore()
        let ca = client(a)
        let cb = client(b)
        let old = Task { try await store.search(prefix: "a", client: ca) }
        await settle { gate.continuation != nil }
        #expect(try await store.search(prefix: "b", client: cb) == ["Beta"])
        a.gate = nil
        a.responses["/Items/Filters"] = Data(#"{"Tags":["Another"]}"#.utf8)
        #expect(try await store.search(prefix: "a", client: ca) == ["Another"])
        gate.finish()
        await #expect(throws: CancellationError.self) { try await old.value }
        #expect(try await store.search(prefix: "a", client: ca) == ["Another"] && a.calls.count == 2)
    }

    @Test
    func `cached tags cannot be read after binding expires`() async throws {
        let s = Sender()
        s.responses["/Items/Filters"] = Data(#"{"Tags":["Alpha"]}"#.utf8)
        let binding = Binding()
        let c = ItemMetadataClient(
            executor: .init(sender: s, isCurrent: { binding.current }),
            userID: "user",
            bindingID: .init(transport: ObjectIdentifier(s), userID: "user")
        )
        let store = MetadataTagSearchStore()
        #expect(try await store.search(prefix: "a", client: c) == ["Alpha"])
        binding.current = false
        await #expect(throws: CancellationError.self) { try await store.search(prefix: "a", client: c) }
        #expect(s.calls.count == 1)
    }
}

@Suite("Item image administration")
@MainActor
struct ItemImageAdministrationTests {
    private func client(_ sender: Sender, binding: Binding? = nil) -> ItemMetadataClient {
        .init(
            executor: .init(sender: sender, isCurrent: { binding?.current ?? true }),
            userID: "exact-user",
            bindingID: .init(transport: ObjectIdentifier(sender), userID: "exact-user")
        )
    }

    @Test
    func `grouping drops untyped and keeps indexed then unindexed stable`() {
        let images: [ImageInfo] = [
            .init(imageIndex: 2, imageType: .backdrop),
            .init(imageType: .primary),
            .init(imageIndex: 0, imageType: .backdrop),
            .init(imageType: .backdrop),
            .init(imageType: .backdrop),
            .init(imageIndex: 3)
        ]
        let grouped = ItemMetadataClient.groupImages(images)
        #expect(Set(grouped.keys) == [.primary, .backdrop])
        #expect(grouped[.backdrop]?.map(\.imageIndex) == [0, 2, nil, nil])
        #expect(grouped[.primary]?.count == 1)
    }

    @Test
    func `image read has exact item and normalizes empty result`() async throws {
        let sender = Sender()
        let images = try await client(sender).itemImages(itemID: "selected")
        #expect(images.isEmpty && sender.calls.count == 1)
        #expect(sender.calls[0].path == "/Items/selected/Images" && sender.calls[0].method == "GET")
    }

    @Test
    func `upload has exactly one base 64 layer and supplied content type`() async throws {
        let sender = Sender()
        let data = Data([0, 1, 2, 255])
        try await client(sender).uploadImage(itemID: "selected", type: .primary, data: data, contentType: "image/png")
        let call = try #require(sender.calls.first)
        #expect(call.path == "/Items/selected/Images/Primary" && call.method == "POST")
        #expect(call.headers == ["Content-Type": "image/png"] && call.rawData == data.base64EncodedData())
    }

    @Test
    func `remote download retains type and URL and rejects incomplete records`() async throws {
        let sender = Sender()
        let c = client(sender)
        #expect(try await !(c.saveRemoteImage(itemID: "selected", image: .init(type: .primary))))
        #expect(try await !(c.saveRemoteImage(itemID: "selected", image: .init(url: "https://example.invalid/image"))))
        #expect(sender.calls.isEmpty)
        #expect(try await c.saveRemoteImage(itemID: "selected", image: .init(type: .backdrop, url: "https://example.invalid/image")))
        #expect(sender.calls[0].path == "/Items/selected/RemoteImages/Download" && sender.calls[0].method == "POST")
        #expect(sender.calls[0].query == ["type": "Backdrop", "imageUrl": "https://example.invalid/image"])
    }

    @Test
    func `indexed and unindexed deletion use distinct SDK routes`() async throws {
        let sender = Sender()
        let c = client(sender)
        #expect(try await !(c.deleteImage(itemID: "selected", image: .init(imageIndex: 1))))
        #expect(sender.calls.isEmpty)
        #expect(try await c.deleteImage(itemID: "selected", image: .init(imageIndex: 3, imageType: .backdrop)))
        #expect(try await c.deleteImage(itemID: "selected", image: .init(imageType: .primary)))
        #expect(sender.calls.map(\.path) == ["/Items/selected/Images/Backdrop/3", "/Items/selected/Images/Primary"])
        #expect(sender.calls.allSatisfy { $0.method == "DELETE" && $0.query.isEmpty })
    }

    @Test
    func `replaced account cannot publish late images`() async {
        let sender = Sender()
        let binding = Binding()
        let gate = Gate()
        sender.gate = gate
        let c = client(sender, binding: binding)
        let task = Task { try await c.itemImages(itemID: "selected") }
        await settle { gate.continuation != nil }
        binding.current = false
        gate.finish()
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(sender.calls.count == 1)
    }

    @Test
    func `expired image write and late failed command become cancellation`() async throws {
        let sender = Sender()
        let binding = Binding()
        binding.current = false
        let c = client(sender, binding: binding)
        await #expect(throws: CancellationError.self) { try await c.uploadImage(
            itemID: "selected",
            type: .primary,
            data: Data(),
            contentType: "image/png"
        ) }
        #expect(sender.calls.isEmpty)
        binding.current = true
        sender.failure = true
        let gate = Gate()
        sender.gate = gate
        let task = Task { try await c.deleteImage(itemID: "selected", image: .init(imageType: .primary)) }
        await settle { gate.continuation != nil }
        binding.current = false
        gate.finish()
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(sender.calls.count == 1)
    }
}
