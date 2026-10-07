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
import Testing

@MainActor
private final class ArtworkReader: MediaCatalogReading {
    var calls: [Request<BaseItemDtoQueryResult>] = []
    var gate: CheckedContinuation<Void, Never>?
    var blocked = false
    func read<Value: Decodable & Sendable>(_ request: Request<Value>) async throws -> Value {
        #expect(request.method == .get && request.body == nil && request.url?.path == "/Items")
        calls.append(Request(path: request.url!.path, method: request.method, query: request.query))
        if blocked {
            await withCheckedContinuation { gate = $0 }
        }
        return try JSONDecoder().decode(Value.self, from: Data("{\"Items\":[{\"Id\":\"synthetic\"}]}".utf8))
    }

    func release() {
        gate?.resume()
        gate = nil
    }
}

@MainActor
private final class ArtworkBinding { var current = true }

struct LibraryCatalogContracts {
    @Test
    func `media type projection preserves repeated order and unknown emptiness`() {
        #expect(MediaCatalogPolicy.libraryItemTypes(for: [.video, .audio, .video, .unknown]) == [
            .episode,
            .movie,
            .video,
            .audio,
            .musicAlbum,
            .episode,
            .movie,
            .video
        ])
        #expect(MediaCatalogPolicy.libraryItemTypes(for: [.unknown]) == [])
        #expect(MediaCatalogPolicy.libraryItemTypes(for: [.book, .photo]) == [.book, .photo])
    }

    @Test @MainActor
    func `artwork requests preserve exact user parent filter and fixed sample size`() async throws {
        let reader = ArtworkReader(), catalog = MediaCatalogClient(reader: reader, userID: "exact-user")
        for scope in [
            LibraryArtworkScope.favorites,
            .userView(.init(collectionType: .movies, id: "library")),
            .userView(.init(collectionType: .livetv, id: "ignored-live-parent"))
        ] {
            _ = try await catalog.page(MediaCatalogPolicy.artworkQuery(for: scope), at: .init(offset: 0, limit: 99))
        }
        let query = reader.calls.map { Dictionary(
            grouping: ($0.query ?? []).compactMap { key, value in value.map { (key, $0) } },
            by: { $0.0 }
        ).mapValues { $0.map(\.1).joined(separator: ",") } }
        #expect(query
            .allSatisfy { $0["userId"] == "exact-user" && $0["limit"] == "3" && $0["sortBy"] == "Random" && $0["recursive"] == "true" })
        #expect(query[0]["filters"] == "IsFavorite" && query[0]["parentId"] == nil)
        #expect(query[1]["filters"] == nil && query[1]["parentId"] == "library")
        #expect(query[2]["parentId"] == nil && query[2]["includeItemTypes"] == "TvProgram,LiveTvProgram")
        #expect(reader.calls.allSatisfy { $0.method == .get && $0.body == nil && $0.url?.path == "/Items" })
    }

    @Test @MainActor
    func `obsolete artwork binding performs no io`() async {
        let reader = ArtworkReader(), binding = ArtworkBinding()
        binding.current = false
        let catalog = MediaCatalogClient(reader: reader, userID: "user", isCurrent: { binding.current })
        do { _ = try await catalog.page(MediaCatalogPolicy.artworkQuery(for: .favorites), at: .init(offset: 0, limit: 3))
            Issue.record("Obsolete request completed")
        } catch { #expect(error is CancellationError) }
        #expect(reader.calls.isEmpty)
    }

    @Test @MainActor
    func `late artwork after account or transport replacement is rejected`() async throws {
        let reader = ArtworkReader(), binding = ArtworkBinding()
        reader.blocked = true
        let catalog = MediaCatalogClient(reader: reader, userID: "user", isCurrent: { binding.current })
        let task = Task { try await catalog.page(MediaCatalogPolicy.artworkQuery(for: .favorites), at: .init(offset: 0, limit: 3)) }
        defer { task.cancel()
            reader.release()
        }
        for _ in 0 ..< 2000 {
            if reader.gate != nil {
                break
            }
            await Task.yield()
        }
        _ = try #require(reader.gate)
        binding.current = false
        reader.release()
        do { _ = try await task.value
            Issue.record("Late obsolete artwork completed")
        } catch { #expect(error is CancellationError) }
        #expect(reader.calls.count == 1)
    }

    @Test @MainActor
    func `cancelled artwork caller rejects noncooperating response`() async throws {
        let reader = ArtworkReader()
        reader.blocked = true
        let catalog = MediaCatalogClient(reader: reader, userID: "user")
        let task = Task { try await catalog.page(MediaCatalogPolicy.artworkQuery(for: .favorites), at: .init(offset: 0, limit: 3)) }
        defer { task.cancel()
            reader.release()
        }
        for _ in 0 ..< 2000 {
            if reader.gate != nil {
                break
            }
            await Task.yield()
        }
        _ = try #require(reader.gate)
        task.cancel()
        reader.release()
        do { _ = try await task.value
            Issue.record("Cancelled artwork completed")
        } catch { #expect(error is CancellationError) }
    }
}
