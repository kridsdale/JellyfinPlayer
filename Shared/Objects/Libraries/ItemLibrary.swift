//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Combine
import Defaults
import JellyfinAPI
import SwiftfinCollections
import SwiftfinLocalization
import SwiftfinMediaCatalog
import SwiftfinPaging
import SwiftfinStoredValues
import SwiftUI

@MainActor
struct ItemLibrary: PagingLibrary, SearchablePagingLibrary, WithRandomElementLibrary {

    struct Environment: WithDefaultValue {
        var grouping: BaseItemDto.Grouping?
        var filters: ItemFilterCollection

        static let `default`: Self = .init(
            grouping: nil,
            filters: .default
        )
    }

    let environment: Environment?
    let filterViewModel: FilterViewModel
    let parent: BaseItemDto

    init(
        parent: BaseItemDto,
        filters: ItemFilterCollection? = nil,
        staticFilters: ItemFilterCollection = .default
    ) {
        var filters = filters ?? .default

        if let id = parent.id, Defaults[.Customization.Library.rememberSort] {
            let storedFilters = StoredValues[.User.libraryFilters(parentID: id)]

            filters.sortBy = storedFilters.sortBy
            filters.sortOrder = storedFilters.sortOrder
        }

        self.environment = .init(
            grouping: parent.groupings?.defaultSelection,
            filters: staticFilters.union(filters)
        )
        self.filterViewModel = .init(
            parent: parent,
            currentFilters: filters,
            staticFilters: staticFilters
        )
        self.parent = parent
    }

    func makeMenuContent(environment: Binding<Environment>) -> AnyView {
        Group {
            if let groupings = parent.groupings, groupings.elements.isNotEmpty {
                Picker(
                    selection: environment.map(
                        getter: { $0.grouping },
                        setter: { .init(grouping: $0, filters: environment.wrappedValue.filters) }
                    )
                ) {
                    ForEach(groupings.elements) { grouping in
                        Text(grouping.displayTitle)
                            .tag(grouping as BaseItemDto.Grouping?)
                    }
                } label: {
                    Text(L10n.grouping)

                    if let grouping = environment.wrappedValue.grouping {
                        Text(grouping.displayTitle)
                    }
                }
                .pickerStyle(.menu)
            }
        }
        .eraseToAnyView()
    }

    func makeLibraryBody(
        viewModel: PagingLibraryViewModel<Self>,
        @ViewBuilder content: @escaping () -> some View
    ) -> AnyView {
        ItemLibraryBody(
            filterViewModel: filterViewModel,
            viewModel: viewModel,
            content: content
        )
        .eraseToAnyView()
    }

    func libraryStyleOptions(environment: Environment) -> LibraryStyleOptions {
        let itemTypes = environment.filters.itemTypes.isEmpty ?
            parent.supportedItemTypes(for: environment.grouping) :
            environment.filters.itemTypes

        return BaseItemKind.libraryStyleOptions(for: itemTypes)
    }

    func retrievePage(
        environment: Environment,
        pageState: LibraryPageState
    ) async throws -> [BaseItemDto] {
        try await retrievePageResult(environment: environment, pageState: pageState).items
    }

    func retrievePageResult(environment: Environment, pageState: LibraryPageState) async throws -> PagingPage<BaseItemDto> {
        try await pageState.mediaPageResult(.items(catalogQuery(environment: environment)))
    }

    func retrieveRandomElement(
        environment: Environment,
        pageState: LibraryPageState
    ) async throws -> BaseItemDto? {
        try await pageState.readMedia(.items(catalogQuery(environment: environment), mode: .random)).items.first
    }

    func retrieveSearchPage(
        query: String,
        environment: Environment,
        pageState: LibraryPageState
    ) async throws -> [BaseItemDto] {
        try await retrieveSearchPageResult(query: query, environment: environment, pageState: pageState).items
    }

    func retrieveSearchPageResult(
        query: String,
        environment: Environment,
        pageState: LibraryPageState
    ) async throws -> PagingPage<BaseItemDto> {
        try await pageState.mediaPageResult(.items(
            catalogQuery(environment: environment),
            mode: .search(query: query, staticQuery: filterViewModel.staticFilters.query)
        ))
    }

    private func catalogQuery(environment: Environment) -> CatalogItemQuery {
        CatalogItemQuery(
            parentID: parent.id,
            parentType: parent.libraryType,
            collectionType: parent.collectionType,
            groupingID: environment.grouping?.id,
            filters: environment.filters.catalogSnapshot
        )
    }
}

private struct ItemLibraryBody<Content: View>: View {

    @Default(.Customization.Library.enabledDrawerFilters)
    private var enabledDrawerFilters

    @Router
    private var router

    @ObservedObject
    private var viewModel: PagingLibraryViewModel<ItemLibrary>

    private let content: Content
    private let filterViewModel: FilterViewModel

    private var filterTypes: [ItemFilterType] {
        enabledDrawerFilters.filter { !filterViewModel.staticFilters.containsFilters(ofType: $0) }
    }

    init(
        filterViewModel: FilterViewModel,
        viewModel: PagingLibraryViewModel<ItemLibrary>,
        @ViewBuilder content: () -> Content
    ) {
        self.filterViewModel = filterViewModel
        self.viewModel = viewModel
        self.content = content()
    }

    var body: some View {
        content
            .onFirstAppear {
                Task {
                    await filterViewModel.getQueryFilters()
                }
            }
            .onChange(of: filterViewModel.currentFilters) {
                rememberSort(from: filterViewModel.currentFilters)
            }
            .onReceive(
                filterViewModel.$currentFilters
                    .map { filterViewModel.staticFilters.union($0) }
                    .removeDuplicates()
                    .debounce(for: 1, scheduler: RunLoop.main)
            ) { filters in
                guard viewModel.environment.filters != filters else { return }
                viewModel.environment.filters = filters
            }
            #if os(tvOS)
            .filterBar(
                viewModel: filterViewModel,
                types: filterTypes
            )
            #endif
            .letterPickerBar(filterViewModel: filterViewModel)
            #if os(tvOS)
            .background(alignment: .top) {
                if !router.isRootOfPath {
                    FocusedPosterCinematicBackgroundView()
                }
            }
            #else
            .navigationBarFilterDrawer(
                viewModel: filterViewModel,
                types: filterTypes
            )
            #endif
    }

    private func rememberSort(from filters: ItemFilterCollection) {
        guard let id = viewModel.library.parent.id,
              Defaults[.Customization.Library.rememberSort]
        else { return }

        let storedFilters = StoredValues[.User.libraryFilters(parentID: id)]
            .mutating(\.sortBy, with: filters.sortBy)
            .mutating(\.sortOrder, with: filters.sortOrder)

        StoredValues[.User.libraryFilters(parentID: id)] = storedFilters
    }
}
