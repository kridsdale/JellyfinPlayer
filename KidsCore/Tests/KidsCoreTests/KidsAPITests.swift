//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation
@testable import KidsCore
import Testing

// Each test gets a distinct host/session. Requests use URLSession's real HTTP decoding
// path, while fixtures contain only synthetic titles and identifiers.
private struct Reply: Sendable {
    var status = 200
    var body: String
}

private final class RequestLog: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [URLRequest] = []
    func append(_ request: URLRequest) {
        lock.lock()
        defer { lock.unlock() }
        storage.append(request)
    }

    var requests: [URLRequest] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }
}

private final class Routes: @unchecked Sendable {
    typealias Handler = @Sendable (URLRequest) -> Reply
    private let lock = NSLock()
    private var handlers: [String: Handler] = [:]
    func put(_ host: String, _ handler: @escaping Handler) {
        lock.lock()
        defer { lock.unlock() }
        handlers[host] = handler
    }

    func get(_ host: String) -> Handler? {
        lock.lock()
        defer { lock.unlock() }
        return handlers[host]
    }
}

private final class FixtureProtocol: URLProtocol, @unchecked Sendable {
    static let routes = Routes()
    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host?.hasSuffix(".test") == true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let host = request.url?.host, let handler = Self.routes.get(host) else {
            client?.urlProtocol(self, didFailWithError: URLError(.cannotConnectToHost))
            return
        }
        let reply = handler(request)
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: reply.status,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(reply.body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private let fixtureBinding = KidsBinding(serverID: "server", userID: "kid", showsID: "tv", moviesID: "movies")
private let policyJSON = #"{"Id":"kid","Policy":{"IsAdministrator":false,"EnableAllFolders":false,"EnableContentDeletion":false,"EnabledFolders":["tv","movies"]}}"#
private let librariesJSON = #"{"Items":[{"Id":"tv","Name":"Kid TV","CollectionType":"tvshows"},{"Id":"movies","Name":"Kid Movies","CollectionType":"movies"}]}"#
private func query(_ request: URLRequest) -> [String: String] {
    Dictionary(uniqueKeysWithValues: (URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems ?? []).map { (
        $0.name,
        $0.value ?? ""
    ) })
}

private func fixture(_ handler: @escaping Routes.Handler) -> (KidsAPI, RequestLog) {
    let host = UUID().uuidString.lowercased() + ".test"
    let log = RequestLog()
    FixtureProtocol.routes.put(host) { request in
        log.append(request)
        if request.url!.path.hasSuffix("/Ancestors") {
            let id = request.url!.pathComponents.dropLast().last ?? ""
            let library = id.hasPrefix("movie") || id == "requested" ? "movies" : "tv"
            return Reply(body: "[{\"Id\":\"\(library)\"}]")
        }
        return handler(request)
    }
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [FixtureProtocol.self]
    config.urlCache = nil
    return (
        KidsAPI(serverURL: URL(string: "https://\(host)/jellyfin")!, token: "fixture-secret", session: URLSession(configuration: config)),
        log
    )
}

private func validRoute(_ request: URLRequest) -> Reply? {
    switch request.url!.path {
    case "/jellyfin/System/Info/Public": Reply(body: #"{"Id":"server","ServerName":"Fixture TV"}"#)
    case "/jellyfin/Users/Me": Reply(body: policyJSON)
    case "/jellyfin/Users/kid/Views": Reply(body: librariesJSON)
    default: nil
    }
}

@Test
func `HTTP validates server user and exact library permissions`() async throws {
    let (api, log) = fixture { validRoute($0) ?? Reply(status: 404, body: "{}") }
    try await api.validate(fixtureBinding)
    #expect(log.requests.count == 3)
    #expect(log.requests.allSatisfy { $0.value(forHTTPHeaderField: "Authorization")?.contains("fixture-secret") == true })
    #expect(log.requests.allSatisfy { $0.url?.absoluteString.contains("fixture-secret") == false })
}

@Test
func `HTTP fails closed on broad or missing policy fields`() async {
    for body in [
        #"{"Id":"kid","Policy":{"IsAdministrator":true,"EnableAllFolders":false,"EnableContentDeletion":false,"EnabledFolders":["tv","movies"]}}"#,
        #"{"Id":"kid","Policy":{"IsAdministrator":false,"EnableAllFolders":true,"EnableContentDeletion":false,"EnabledFolders":["tv","movies"]}}"#,
        #"{"Id":"kid","Policy":{"IsAdministrator":false,"EnableAllFolders":false,"EnableContentDeletion":true,"EnabledFolders":["tv","movies"]}}"#,
        #"{"Id":"kid","Policy":{}}"#
    ] {
        let (api, log) = fixture { request in
            request.url!.path.hasSuffix("Users/Me") ? Reply(body: body) : validRoute(request) ?? Reply(status: 404, body: "{}")
        }
        await #expect(throws: KidsAPIError.policy) { try await api.validate(fixtureBinding) }
        #expect(!log.requests.contains { $0.url!.path.hasSuffix("Views") })
    }
}

@Test
func `HTTP stops immediately on expired token without catalog fallback`() async {
    let (api, log) = fixture { request in
        request.url!.path.hasSuffix("Users/Me") ? Reply(status: 401, body: "expired") : validRoute(request) ?? Reply(
            status: 404,
            body: "{}"
        )
    }
    await #expect(throws: KidsAPIError.authentication) { try await api.authorize(
        itemID: "a",
        expectedKind: .episode,
        binding: fixtureBinding
    ) }
    #expect(log.requests.count == 2)
    #expect(!log.requests.contains { $0.url!.path.hasSuffix("Items") })
}

@Test
func `HTTP rejects changed server user or library binding`() async {
    for (path, body, expected) in [
        ("System/Info/Public", #"{"Id":"other","ServerName":"Other"}"#, KidsAPIError.libraryChanged),
        ("Users/Me", policyJSON.replacingOccurrences(of: "\"kid\"", with: "\"other\""), .authentication),
        (
            "Users/kid/Views",
            #"{"Items":[{"Id":"tv","Name":"Kid TV","CollectionType":"tvshows"},{"Id":"other","Name":"Kid Movies","CollectionType":"movies"}]}"#,
            .libraryChanged
        )
    ] {
        let (api, _) = fixture { request in
            request.url!.path.hasSuffix(path) ? Reply(body: body) : validRoute(request) ?? Reply(status: 404, body: "{}")
        }
        await #expect(throws: expected) { try await api.validate(fixtureBinding) }
    }
}

@Test
func `HTTP pagination retains explicit parent scope and filters unsupported types`() async throws {
    let (api, log) = fixture { request in
        let q = query(request)
        if q["StartIndex"] == "0" {
            return Reply(
                body: #"{"TotalRecordCount":3,"Items":[{"Id":"a","Name":"First","Type":"Series"},{"Id":"extra","Name":"Extra","Type":"Trailer"}]}"#
            )
        }
        return Reply(body: #"{"TotalRecordCount":3,"Items":[{"Id":"b","Name":"Second","Type":"Series"}]}"#)
    }
    let values = try await api.catalog(.shows, binding: fixtureBinding)
    #expect(values.map(\.id) == ["a", "b"])
    #expect(log.requests.filter { $0.url!.path.hasSuffix("/Items") }.map { query($0)["StartIndex"] } == ["0", "2"])
    #expect(log.requests.filter { $0.url!.path.hasSuffix("/Items") }
        .allSatisfy { query($0)["ParentId"] == "tv" && query($0)["UserId"] == "kid" && query($0)["Recursive"] == "true" })
    #expect(values.allSatisfy { $0.libraryID == "tv" })
}

@Test
func `HTTP direct item lookup cannot accept a different identifier or media type`() async throws {
    for body in [
        #"{"Items":[{"Id":"other","Name":"Other","Type":"Movie"}]}"#,
        #"{"Items":[{"Id":"requested","Name":"Wrong type","Type":"Series"}]}"#,
        #"{"Items":[]}"#
    ] {
        let (api, log) = fixture { request in validRoute(request) ?? Reply(body: body) }
        await #expect(throws: KidsContractError.denied) { try await api.authorize(
            itemID: "requested",
            expectedKind: .movie,
            binding: fixtureBinding
        ) }
        #expect(try query(#require(log.requests.last))["ParentId"] == "movies")
        #expect(try query(#require(log.requests.last))["Ids"] == "requested")
    }
}

@Test
func `HTTP episode list excludes specials unrelated shows and virtual items`() async throws {
    let (api, _) = fixture { request in
        if let reply = validRoute(request) {
            return reply
        }
        if query(request)["Ids"] == "show" {
            return Reply(body: #"{"Items":[{"Id":"show","Name":"Show","Type":"Series"}]}"#)
        }
        return Reply(
            body: #"{"Items":[{"Id":"b","Name":"Second","Type":"Episode","SeriesId":"show","ParentIndexNumber":1,"IndexNumber":2},{"Id":"special","Name":"Special","Type":"Episode","SeriesId":"show","ParentIndexNumber":0,"IndexNumber":1},{"Id":"unrelated","Name":"Other","Type":"Episode","SeriesId":"other","ParentIndexNumber":1,"IndexNumber":1},{"Id":"virtual","Name":"Missing","Type":"Episode","LocationType":"Virtual","SeriesId":"show","ParentIndexNumber":1,"IndexNumber":9},{"Id":"a","Name":"First","Type":"Episode","SeriesId":"show","ParentIndexNumber":1,"IndexNumber":1}]}"#
        )
    }
    #expect(try await api.episodes(showID: "show", binding: fixtureBinding).map(\.id) == ["a", "b"])
}

@Test
func `HTTP malformed responses and absent videos remain failures`() async {
    for (reply, expected) in [
        (Reply(body: "not json"), KidsAPIError.invalidResponse),
        (Reply(status: 404, body: "{}"), .unavailable),
        (Reply(status: 503, body: "{}"), .connection)
    ] {
        let (api, _) = fixture { _ in reply }
        await #expect(throws: expected) { try await api.serverInfo() }
    }
}

@Test
func `artwork permits only an eligible item's own or show image owner`() throws {
    let (api, _) = fixture { _ in Reply(status: 404, body: "{}") }
    var item = KidsItem(id: "show", name: "Show", kind: .series, libraryID: "tv", imageTag: "tag", imageOwnerID: "show")
    let request = try api.imageRequest(for: item, binding: fixtureBinding)
    #expect(request.url?.path == "/jellyfin/Items/show/Images/Primary")
    #expect(try !#require(request.url?.absoluteString.contains("fixture-secret")))
    item.imageOwnerID = "outside"
    #expect(throws: KidsContractError.denied) { try api.imageRequest(for: item, binding: fixtureBinding) }
    item.libraryID = "outside"
    #expect(throws: KidsContractError.denied) { try api.imageRequest(for: item, binding: fixtureBinding) }
}

@Test
func `forged same-type upstream catalog item never enters approved results`() async throws {
    let host = UUID().uuidString.lowercased() + ".test"
    let log = RequestLog()
    FixtureProtocol.routes.put(host) { request in
        log.append(request)
        if request.url!.path.hasSuffix("approved/Ancestors") {
            return Reply(body: #"[{"Id":"tv"}]"#)
        }
        if request.url!.path.hasSuffix("forbidden/Ancestors") {
            return Reply(body: #"[{"Id":"other-library"}]"#)
        }
        if let response = validRoute(request) {
            return response
        }
        return Reply(
            body: #"{"Items":[{"Id":"approved","Name":"Allowed fixture","Type":"Series"},{"Id":"forbidden","Name":"Denied fixture","Type":"Series"}]}"#
        )
    }
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [FixtureProtocol.self]
    let api = try KidsAPI(
        serverURL: #require(URL(string: "https://\(host)/jellyfin")),
        token: "fixture-secret",
        session: URLSession(configuration: config)
    )
    let catalog = try await api.catalog(.shows, binding: fixtureBinding)
    #expect(catalog.map(\.id) == ["approved"])
    #expect(!log.requests.contains { $0.url!.path.contains("Images") })
    await #expect(throws: KidsContractError.denied) { try await api.authorize(
        itemID: "forbidden",
        expectedKind: .series,
        binding: fixtureBinding
    ) }
}

@Test
func `episode pagination uses the authorized show endpoint and never walks the library`() async throws {
    let (api, log) = fixture { request in
        if let reply = validRoute(request) {
            return reply
        }
        if request.url?.path.hasSuffix("/Items") == true {
            return Reply(body: #"{"Items":[{"Id":"show","Name":"Show","Type":"Series"}]}"#)
        }
        guard request.url?.path.hasSuffix("/Shows/show/Episodes") == true else { return Reply(status: 404, body: "{}") }
        if query(request)["StartIndex"] == "0" {
            return Reply(
                body: #"{"TotalRecordCount":2,"Items":[{"Id":"a","Name":"One","Type":"Episode","SeriesId":"show","ParentIndexNumber":1,"IndexNumber":1}]}"#
            )
        }
        return Reply(
            body: #"{"TotalRecordCount":2,"Items":[{"Id":"b","Name":"Two","Type":"Episode","SeriesId":"show","ParentIndexNumber":1,"IndexNumber":2}]}"#
        )
    }
    let episodes = try await api.episodes(showID: "show", binding: fixtureBinding)
    #expect(episodes.map(\.id) == ["a", "b"])
    let pages = log.requests.filter { $0.url?.path.hasSuffix("/Episodes") == true }
    #expect(pages.count == 2)
    #expect(pages.map { query($0)["StartIndex"] } == ["0", "1"])
    #expect(pages.allSatisfy { query($0)["UserId"] == "kid" && query($0)["SeriesId"] == nil })
    let libraryRequests = log.requests.filter { $0.url?.path.hasSuffix("/Items") == true }
    #expect(libraryRequests.count == 1)
    #expect(libraryRequests.allSatisfy { query($0)["ParentId"] == "tv" && query($0)["Ids"] == "show" })
}
