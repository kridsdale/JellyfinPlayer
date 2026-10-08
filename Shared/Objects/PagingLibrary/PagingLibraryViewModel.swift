//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import CasePaths
import Combine
import FactoryKit
import Foundation
import IdentifiedCollections
import JellyfinAPI
import StatefulMacros
import SwiftfinAsyncStreams
import SwiftfinCollections
import SwiftfinNetworking
import SwiftfinPaging
import SwiftfinTime

let defaultPagingLibraryPageSize = 50

@MainActor
@Stateful(conformances: [WithRefresh.self])
class PagingLibraryViewModel<Library: PagingLibrary>: ViewModel, Identifiable, WithRefreshScope {

    typealias Background = _BackgroundActions
    typealias Element = Library.Element
    typealias Environment = Library.Environment

    @CasePathable
    enum Action {
        case refresh
        case getNextPage
        case getRandomItem
        case getNextSearchPage
        case search(query: String)

        case _actuallyGetNextPage

        var transition: Transition {
            switch self {
            case .refresh:
                .to(.refreshing, then: .content)
                    .whenBackground(.refreshing)
            case .getNextPage:
                .none
            case .getRandomItem:
                .background(.gettingRandomItem)
            case .getNextSearchPage:
                .background(.gettingNextSearchPage)
            case .search:
                .background(.searching)
                    .onRepeat(.cancel)
            case ._actuallyGetNextPage:
                .background(.gettingNextPage)
            }
        }
    }

    enum BackgroundState {
        case refreshing
        case gettingNextPage
        case gettingRandomItem
        case gettingNextSearchPage
        case searching
    }

    enum Event {
        case gotRandomItem(Element)
    }

    enum State {
        case content
        case error
        case initial
        case refreshing
    }

    @Published
    private(set) var elements: IdentifiedArrayOf<Element>
    @Published
    var environment: Environment {
        didSet { invalidatePaging() }
    }

    @Published
    private(set) var searchElements: IdentifiedArrayOf<Element>
    @Published
    var searchQuery: String = "" {
        didSet { paging.prepareSearch(searchQuery) }
    }

    let library: Library
    let pageSize: Int
    private let paging: PagingStore<Element>
    private let refreshScheduler = PagingRefreshScheduler()
    private var sourceIdentity = UUID()
    private var sourceSession: UserSession?
    private var sourceClient: JellyfinTransport?
    private var refreshScope: ContentRefreshOperation.Checkpoint = {}

    func bindRefreshScope(_ validate: @escaping ContentRefreshOperation.Checkpoint) throws {
        try validate()
        refreshScope = validate
        invalidatePaging()
        try validate()
    }

    nonisolated let id: String

    var isSearchActive: Bool {
        normalizedSearchQuery.isNotEmpty
    }

    var isSearchSupported: Bool {
        searchableLibrary != nil
    }

    var displayedElements: IdentifiedArrayOf<Element> {
        isSearchActive ? searchElements : elements
    }

    private var normalizedSearchQuery: String {
        searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var searchableLibrary: (any SearchablePagingLibrary<Element, Environment>)? {
        library as? any SearchablePagingLibrary<Element, Environment>
    }

    init(library: Library, pageSize: Int = defaultPagingLibraryPageSize, validate: @escaping ContentRefreshOperation.Checkpoint = {}) {
        self.refreshScope = validate
        self.elements = IdentifiedArray([], uniquingIDsWith: { existing, _ in existing })
        self.environment = library.environment ?? .default
        self.searchElements = IdentifiedArray([], uniquingIDsWith: { existing, _ in existing })
        self.id = library.parent.pagingLibraryID
        self.library = library
        self.paging = PagingStore(pageSize: pageSize)
        self.pageSize = max(1, pageSize)
        super.init()

        paging.$elements.sink { [weak self] rows in
            self?.elements = IdentifiedArray(rows, uniquingIDsWith: { existing, _ in existing })
        }.store(in: &cancellables)
        paging.$searchElements.sink { [weak self] rows in
            self?.searchElements = IdentifiedArray(rows, uniquingIDsWith: { existing, _ in existing })
        }.store(in: &cancellables)
        Container.shared.userSessionManager().$currentSession.dropFirst().sink { [weak self] _ in
            self?.invalidatePaging()
        }.store(in: &cancellables)
        Notifications[.didChangeServerConnection].publisher.sink { [weak self] _ in
            self?.invalidatePaging()
        }.store(in: &cancellables)
        Notifications[.didDeleteItem].publisher.sink { [weak self] id in
            self?.removeDeletedItem(withID: id)
        }.store(in: &cancellables)
        Notifications[.itemUserDataDidChange].publisher.sink { [weak self] userData in
            guard let self else { return }
            updateItemUserData(userData)
            library.onItemUserDataChanged(viewModel: self, userData: userData)
        }.store(in: &cancellables)
        $searchQuery.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .removeDuplicates().debounce(for: .milliseconds(350), scheduler: RunLoop.main)
            .sink { [weak self] query in self?.search(query: query) }
            .store(in: &cancellables)
    }

    private func invalidatePaging() {
        sourceIdentity = UUID()
        sourceSession = nil
        sourceClient = nil
        refreshScheduler.cancel()
        paging.invalidate()
    }

    func refreshForEnvironmentChange() {
        if isSearchActive {
            search(query: normalizedSearchQuery)
        } else {
            refresh()
        }
    }

    func removeElements(where predicate: (Element) -> Bool) {
        paging.remove(where: predicate)
    }

    private func removeDeletedItem(withID id: String) {
        paging.remove { element in
            if let item = element as? BaseItemDto {
                return item.id == id
            }
            if let user = element as? UserDto {
                return user.id == id
            }
            if let elementID = element.id as? String {
                return elementID == id
            }
            if let elementID = element.id as? String? {
                return elementID == id
            }
            return false
        }
    }

    private func updateItemUserData(_ userData: UserItemDataDto) {
        guard let itemID = userData.itemID else { return }
        paging.update { element in
            guard var item = element as? BaseItemDto, item.id == itemID else { return element }
            item.userData = userData
            return (item as? Element) ?? element
        }
    }

    func scheduleRefreshForItemUserData(debounce: TimeInterval = 0.35, minimumInterval: TimeInterval = 5) {
        guard debounce.isFinite, minimumInterval.isFinite else { return }
        refreshScheduler.schedule(debounce: .seconds(max(0, debounce)), minimumInterval: .seconds(max(0, minimumInterval))) { [weak self] in
            await self?.background.refresh()
        }
    }

    @Function(\Action.Cases.refresh)
    private func _refresh() async throws {
        try await paging.refresh(using: makeSource(), retainingContent: StateTask.isBackground)
    }

    @Function(\Action.Cases.getNextPage)
    private func _getNextPage() async throws {
        guard paging.hasMore else { return }
        await _actuallyGetNextPage()
    }

    @Function(\Action.Cases._actuallyGetNextPage)
    private func __actuallyGetNextPage() async throws {
        try await paging.nextPage(using: makeSource())
    }

    @Function(\Action.Cases.search)
    private func _search(_ query: String) async throws {
        guard query == normalizedSearchQuery else { return }
        try await paging.search(query, using: makeSource())
    }

    @Function(\Action.Cases.getNextSearchPage)
    private func _getNextSearchPage() async throws {
        guard isSearchActive, !background.is(.searching) else { return }
        try await paging.nextSearchPage(using: makeSource())
    }

    @Function(\Action.Cases.getRandomItem)
    private func _getRandomItem() async throws {
        guard let element = try await paging.randomElement(using: makeSource()) else { return }
        events.send(.gotRandomItem(element))
    }

    /// Bind once before suspension; request adapters cannot reread a replacement transport.
    private func makeSource() throws -> PagingSource<Element> {
        let refreshScope = refreshScope
        try refreshScope()
        let manager = Container.shared.userSessionManager()
        guard let session = manager.currentSession else { throw UserSessionError.missingCurrentSession }
        let client = session.client
        if sourceSession !== session || sourceClient !== client {
            invalidatePaging()
            sourceSession = session
            sourceClient = client
        }
        try refreshScope()
        let identity = sourceIdentity
        let environment = environment
        let library = library
        let userID = session.user.id
        let state: @MainActor @Sendable (PagingRequest) -> LibraryPageState = { request in
            LibraryPageState(pageOffset: request.offset, pageSize: request.limit, client: client, userID: userID)
        }
        let search: PagingSource<Element>.Load? = if let searchable = searchableLibrary {
            { request in
                try await searchable.retrieveSearchPageResult(
                    query: request.query ?? "",
                    environment: environment,
                    pageState: state(request)
                )
            }
        } else {
            nil
        }
        let random: (@MainActor @Sendable () async throws -> Element?)? = if let randomLibrary = library as? any WithRandomElementLibrary<
            Element,
            Environment
        > {
            { try await randomLibrary.retrieveRandomElement(environment: environment, pageState: state(PagingRequest(offset: 0, limit: 1)))
            }
        } else {
            nil
        }
        return PagingSource(identity: identity, canPage: library.hasNextPage, isCurrent: { [weak self, weak session] in
            guard let self, let session, (try? refreshScope()) != nil else { return false }
            return sourceIdentity == identity && manager.currentSession === session && session.client === client
        }, load: { request in
            try await library.retrievePageResult(environment: environment, pageState: state(request))
        }, search: search, random: random)
    }
}

extension PagingLibraryViewModel: @MainActor Displayable {

    var displayTitle: String {
        library.parent.displayTitle
    }
}

extension PagingLibraryViewModel where Element: LibraryElement {

    var libraryStyleOptions: LibraryStyleOptions {
        library.resolvedLibraryStyleOptions(
            environment: environment,
            elements: displayedElements
        )
    }
}
