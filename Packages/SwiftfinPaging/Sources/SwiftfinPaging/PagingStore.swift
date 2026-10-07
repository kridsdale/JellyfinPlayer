//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Combine
import Foundation

@MainActor
public final class PagingStore<Element: Identifiable>: ObservableObject {
    @Published
    public private(set) var elements: [Element] = []
    @Published
    public private(set) var searchElements: [Element] = []
    @Published
    public private(set) var hasMore = true
    @Published
    public private(set) var hasMoreSearch = false
    public let pageSize: Int
    private var sourceID: UUID?
    private var binding = UUID()
    private var mainGeneration = UUID()
    private var searchGeneration = UUID()
    private var mainFlight: UUID?
    private var searchFlight: UUID?
    private var offset = 0
    private var searchOffset = 0
    private var query = ""

    public init(pageSize: Int = 50) {
        self.pageSize = max(1, pageSize)
    }

    public func invalidate() {
        sourceID = nil
        binding = UUID()
        mainGeneration = UUID()
        searchGeneration = UUID()
        mainFlight = nil
        searchFlight = nil
        offset = 0
        searchOffset = 0
        query = ""
        elements = []
        searchElements = []
        hasMore = true
        hasMoreSearch = false
    }

    public func refresh(using source: PagingSource<Element>, retainingContent: Bool = false) async throws {
        try activate(source)
        mainGeneration = UUID()
        mainFlight = nil
        if !retainingContent {
            offset = 0
            hasMore = true
            elements = []
        }
        try await mainPage(source, replacing: true)
    }

    public func nextPage(using source: PagingSource<Element>) async throws {
        try activate(source)
        guard hasMore, mainFlight == nil else { return }
        try await mainPage(source, replacing: false)
    }

    public func search(_ value: String, using source: PagingSource<Element>) async throws {
        try activate(source)
        prepareSearch(value)
        hasMoreSearch = !query.isEmpty && source.search != nil
        if hasMoreSearch {
            try await searchPage(source)
        }
    }

    /// Revoke the previous query immediately, before a presentation debounce elapses.
    public func prepareSearch(_ value: String) {
        query = value.trimmingCharacters(in: .whitespacesAndNewlines)
        searchGeneration = UUID()
        searchFlight = nil
        searchOffset = 0
        searchElements = []
        hasMoreSearch = false
    }

    public func nextSearchPage(using source: PagingSource<Element>) async throws {
        try activate(source)
        guard hasMoreSearch, searchFlight == nil else { return }
        try await searchPage(source)
    }

    public func randomElement(using source: PagingSource<Element>) async throws -> Element? {
        try activate(source)
        let epoch = binding
        let value: Element?
        do {
            if let random = source.random {
                value = try await random()
            } else {
                value = elements.randomElement()
            }
        } catch {
            try validate(source, binding: epoch)
            throw error
        }
        try validate(source, binding: epoch)
        return value
    }

    /// Notification-driven removal does not rewind the consumed server cursor.
    public func remove(where predicate: (Element) -> Bool) {
        elements.removeAll(where: predicate)
        searchElements.removeAll(where: predicate)
    }

    public func update(_ transform: (Element) -> Element) {
        elements = unique(elements.map(transform))
        searchElements = unique(searchElements.map(transform))
    }

    private func activate(_ source: PagingSource<Element>) throws {
        try Task.checkCancellation()
        guard source.isCurrent() else {
            if sourceID == source.identity {
                invalidate()
            }
            throw CancellationError()
        }
        if sourceID != source.identity {
            invalidate()
            sourceID = source.identity
        }
    }

    private func validate(_ source: PagingSource<Element>, binding epoch: UUID) throws {
        guard binding == epoch, sourceID == source.identity else { throw CancellationError() }
        guard source.isCurrent() else { invalidate()
            throw CancellationError()
        }
        try Task.checkCancellation()
    }

    private func mainPage(_ source: PagingSource<Element>, replacing: Bool) async throws {
        let epoch = binding, generation = mainGeneration, flight = UUID()
        let request = PagingRequest(offset: replacing ? 0 : offset, limit: pageSize)
        mainFlight = flight
        defer {
            if mainFlight == flight {
                mainFlight = nil
            }
        }
        let page: PagingPage<Element>
        do { page = try await source.load(request) }
        catch {
            guard mainGeneration == generation, mainFlight == flight else { throw CancellationError() }
            try validate(source, binding: epoch)
            throw error
        }
        guard mainGeneration == generation, mainFlight == flight else { throw CancellationError() }
        try validate(source, binding: epoch)
        let next = request.offset.addingReportingOverflow(page.consumedCount)
        guard !next.overflow else { throw PagingError.cursorOverflow }
        offset = next.partialValue
        hasMore = source.canPage && page.consumedCount >= pageSize
        elements = unique((replacing ? [] : elements) + page.items)
    }

    private func searchPage(_ source: PagingSource<Element>) async throws {
        guard let load = source.search else { return }
        let epoch = binding, generation = searchGeneration, flight = UUID()
        let request = PagingRequest(offset: searchOffset, limit: pageSize, query: query)
        searchFlight = flight
        defer {
            if searchFlight == flight {
                searchFlight = nil
            }
        }
        let page: PagingPage<Element>
        do { page = try await load(request) }
        catch {
            guard searchGeneration == generation, searchFlight == flight else { throw CancellationError() }
            try validate(source, binding: epoch)
            throw error
        }
        guard searchGeneration == generation, searchFlight == flight else { throw CancellationError() }
        try validate(source, binding: epoch)
        let next = request.offset.addingReportingOverflow(page.consumedCount)
        guard !next.overflow else { throw PagingError.cursorOverflow }
        searchOffset = next.partialValue
        hasMoreSearch = source.canPage && page.consumedCount >= pageSize
        searchElements = unique(searchElements + page.items)
    }

    private func unique(_ items: [Element]) -> [Element] {
        var seen: Set<Element.ID> = []
        return items.filter { seen.insert($0.id).inserted }
    }
}

public enum PagingError: Error, Sendable { case cursorOverflow }
