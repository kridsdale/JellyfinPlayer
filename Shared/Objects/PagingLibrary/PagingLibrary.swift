//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import JellyfinAPI
import SwiftfinNetworking
import SwiftfinPaging
import SwiftUI

@MainActor
struct LibraryPageState {
    let pageOffset: Int
    let pageSize: Int
    let client: JellyfinTransport
    let userID: String

    init(pageOffset: Int, pageSize: Int, client: JellyfinTransport, userID: String) {
        self.pageOffset = pageOffset
        self.pageSize = pageSize
        self.client = client
        self.userID = userID
    }

    init(pageOffset: Int, pageSize: Int, userSession: UserSession) {
        self.init(pageOffset: pageOffset, pageSize: pageSize, client: userSession.client, userID: userSession.user.id)
    }
}

@MainActor
protocol PagingLibrary<Element>: Sendable, SendableMetatype {

    associatedtype Element: Identifiable
    associatedtype Environment: WithDefaultValue = Empty
    associatedtype Parent: LibraryParent = TitledLibraryParent

    var environment: Environment? { get }
    var hasNextPage: Bool { get }
    var parent: Parent { get }

    func retrievePage(
        environment: Environment,
        pageState: LibraryPageState
    ) async throws -> [Element]

    func retrievePageResult(environment: Environment, pageState: LibraryPageState) async throws -> PagingPage<Element>

    @ViewBuilder
    func makeLibraryBody(
        viewModel: PagingLibraryViewModel<Self>,
        @ViewBuilder content: @escaping () -> some View
    ) -> AnyView

    func libraryStyleOptions(environment: Environment) -> LibraryStyleOptions

    func makeMenuContent(environment: Binding<Environment>) -> AnyView

    func onItemUserDataChanged(
        viewModel: PagingLibraryViewModel<Self>,
        userData: UserItemDataDto
    )
}

extension PagingLibrary where Element: LibraryElement {

    func libraryStyleOptions(environment: Environment) -> LibraryStyleOptions {
        Element.supportedLibraryStyleOptions
    }

    func resolvedLibraryStyleOptions(
        environment: Environment,
        elements: some Sequence<Element>
    ) -> LibraryStyleOptions {
        LibraryStyleOptions.resolving(
            elements.map(\.supportedLibraryStyleOptions),
            fallback: libraryStyleOptions(environment: environment)
        )
    }
}

extension PagingLibrary {

    func retrievePageResult(environment: Environment, pageState: LibraryPageState) async throws -> PagingPage<Element> {
        try await PagingPage(items: retrievePage(environment: environment, pageState: pageState))
    }

    var environment: Environment? {
        nil
    }

    var hasNextPage: Bool {
        true
    }

    func makeLibraryBody(
        viewModel: PagingLibraryViewModel<Self>,
        @ViewBuilder content: @escaping () -> some View
    ) -> AnyView {
        content()
            .eraseToAnyView()
    }

    func libraryStyleOptions(environment: Environment) -> LibraryStyleOptions {
        .default
    }

    func makeMenuContent(environment: Binding<Environment>) -> AnyView {
        EmptyView()
            .eraseToAnyView()
    }

    func onItemUserDataChanged(
        viewModel: PagingLibraryViewModel<Self>,
        userData: UserItemDataDto
    ) {}
}

protocol WithRandomElementLibrary<Element, Environment>: PagingLibrary {

    func retrieveRandomElement(
        environment: Environment,
        pageState: LibraryPageState
    ) async throws -> Element?
}

protocol SearchablePagingLibrary<Element, Environment>: PagingLibrary {

    func retrieveSearchPageResult(query: String, environment: Environment, pageState: LibraryPageState) async throws -> PagingPage<Element>

    func retrieveSearchPage(
        query: String,
        environment: Environment,
        pageState: LibraryPageState
    ) async throws -> [Element]
}

extension SearchablePagingLibrary {
    func retrieveSearchPageResult(
        query: String,
        environment: Environment,
        pageState: LibraryPageState
    ) async throws -> PagingPage<Element> {
        try await PagingPage(items: retrieveSearchPage(query: query, environment: environment, pageState: pageState))
    }
}
