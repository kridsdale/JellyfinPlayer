//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Defaults
import FactoryKit
import JellyfinAPI
import SwiftfinCollections
import SwiftfinImages
import SwiftfinLocalization
import SwiftfinMediaCatalog
import SwiftfinText
import SwiftUI

private let userViewLibraryListImageWidth: CGFloat = 110

struct UserViewLibrary: PagingLibrary {

    let hasNextPage: Bool = false
    let parent: TitledLibraryParent = .init(
        displayTitle: L10n.media,
        id: "user-views"
    )

    func libraryStyleOptions(environment: Empty) -> LibraryStyleOptions {
        UserViewLibraryElement.supportedLibraryStyleOptions
    }

    func retrievePage(
        environment: Empty,
        pageState: LibraryPageState
    ) async throws -> [UserViewLibraryElement] {
        guard pageState.pageOffset == 0 else { return [] }
        let items = try await pageState.mediaCatalog.userViews()
        return items.map(UserViewLibraryElement.userView).prepending(.favorites, if: Defaults[.Customization.Library.showFavorites])
    }
}

enum UserViewLibraryElement: Displayable, Hashable, Identifiable, LibraryElement, SystemImageable {

    case favorites
    case userView(BaseItemDto)

    static var supportedLibraryStyleOptions: LibraryStyleOptions {
        BaseItemKind.libraryStyleOptions(for: [.userView])
    }

    nonisolated var displayTitle: String {
        switch self {
        case .favorites:
            L10n.favorites
        case let .userView(item):
            item.displayTitle
        }
    }

    nonisolated var id: String {
        switch self {
        case .favorites:
            "favorites"
        case let .userView(item):
            item.id ?? item.displayTitle
        }
    }

    nonisolated var systemImage: String {
        switch self {
        case .favorites:
            "heart.fill"
        case let .userView(item):
            if item.collectionType == .livetv {
                "tv"
            } else {
                "folder.fill"
            }
        }
    }

    func libraryDidSelectElement(
        router: Router.Wrapper,
        in namespace: Namespace.ID
    ) {
        switch self {
        case .favorites:
            router.route(
                to: .contentGroup(
                    provider: ItemTypeContentGroupProvider(
                        itemTypes: [
                            BaseItemKind.movie,
                            .series,
                            .boxSet,
                            .episode,
                            .musicVideo,
                            .video,
                            .liveTvProgram,
                            .tvChannel,
                            .musicArtist,
                            .person,
                        ],
                        parent: .init(name: L10n.favorites),
                        environment: .init(filters: .favorites)
                    )
                ),
                in: namespace
            )
        case let .userView(item):
            if item.collectionType == .livetv {
                router.route(to: .liveTV, in: namespace)
            } else {
                router.route(
                    to: .library(library: ItemLibrary(parent: item, filters: .default)),
                    in: namespace
                )
            }
        }
    }

    @ViewBuilder
    func makeBody(
        libraryStyle: LibraryStyle,
        action: (() -> Void)?
    ) -> some View {
        switch libraryStyle.displayType {
        case .grid:
            UserViewLibraryGridElement(element: self)
        case .list:
            UserViewLibraryListElement(element: self)
        }
    }
}

private struct UserViewLibraryGridElement: View {

    @Default(.Customization.Library.randomImage)
    private var useRandomImage

    @Namespace
    private var namespace

    @Router
    private var router

    @State
    private var imageSources: [ImageSource] = []

    let element: UserViewLibraryElement

    private var isTitleLabelVisible: Bool {
        switch element {
        case .favorites:
            true
        case .userView:
            useRandomImage
        }
    }

    var body: some View {
        Button {
            element.libraryDidSelectElement(router: router, in: namespace)
        } label: {
            ImageView(imageSources)
                .image { image in
                    if isTitleLabelVisible {
                        titleLabelOverlay(with: image)
                    } else {
                        image
                    }
                }
                .placeholder { imageSource in
                    titleLabelOverlay(with: DefaultPlaceholderView(blurHash: imageSource.blurHash))
                }
                .failure {
                    Color.secondarySystemFill
                        .opacity(0.75)
                        .overlay {
                            titleLabel
                                .foregroundStyle(.primary)
                        }
                }
                .id(imageSources.hashValue)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .posterStyle(.landscape)
                .matchedTransitionSource(id: "item", in: namespace)
        }
        .task(id: UserViewArtworkRequest(element: element, random: useRandomImage)) {
            await setImageSources()
        }
        .buttonStyle(.card)
    }

    @ViewBuilder
    private var titleLabel: some View {
        Text(element.displayTitle)
            .font(.title2)
            .fontWeight(.semibold)
            .lineLimit(1)
            .multilineTextAlignment(.center)
            .frame(alignment: .center)
    }

    private func titleLabelOverlay(with content: some View) -> some View {
        ZStack {
            content

            Color.black
                .opacity(0.5)

            titleLabel
                .foregroundStyle(.white)
        }
    }

    private func setImageSources() async {
        let sources = await element.libraryImageSources(useRandomImage: useRandomImage)
        guard !Task.isCancelled else { return }
        imageSources = sources
    }
}

private struct UserViewLibraryListElement: View {

    @Default(.Customization.Library.randomImage)
    private var useRandomImage

    @Namespace
    private var namespace

    @Router
    private var router

    @State
    private var imageSources: [ImageSource] = []

    let element: UserViewLibraryElement

    var body: some View {
        ListRow(insets: .init(vertical: 8, horizontal: EdgeInsets.edgePadding)) {
            imageView
        } content: {
            Text(element.displayTitle)
                .font(.callout)
                .fontWeight(.semibold)
                .foregroundStyle(.primary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
        } action: {
            element.libraryDidSelectElement(router: router, in: namespace)
        }
        #if !os(tvOS)
        .matchedTransitionSource(id: "item", in: namespace)
        #endif
        .task(id: UserViewArtworkRequest(element: element, random: useRandomImage)) {
            await setImageSources()
        }
    }

    private var imageView: some View {
        ZStack {
            Color.secondarySystemFill
                .opacity(0.75)

            ImageView(imageSources)
                .placeholder { imageSource in
                    DefaultPlaceholderView(blurHash: imageSource.blurHash)
                }
                .failure {
                    Image(systemName: element.systemImage)
                        .foregroundStyle(.secondary)
                }
                .id(imageSources.hashValue)
        }
        .posterStyle(.landscape)
        .subtleShadow()
        .frame(width: userViewLibraryListImageWidth)
    }

    private func setImageSources() async {
        let sources = await element.libraryImageSources(useRandomImage: useRandomImage)
        guard !Task.isCancelled else { return }
        imageSources = sources
    }
}

private struct UserViewArtworkRequest: Hashable {
    let element: UserViewLibraryElement
    let random: Bool
}

private extension UserViewLibraryElement {

    @MainActor
    func libraryImageSources(useRandomImage: Bool) async -> [ImageSource] {
        switch self {
        case .favorites:
            return await (try? randomItemImageSources()) ?? []
        case let .userView(item):
            if useRandomImage {
                return await (try? randomItemImageSources()) ?? []
            }

            return [item.imageSource(.primary, itemID: item.id, environment: ImageSourceOptions(maxWidth: 500))].compactMap(\.self)
        }
    }

    @MainActor
    func randomItemImageSources() async throws -> [ImageSource] {
        let manager = Container.shared.userSessionManager()
        guard let session = manager.currentSession else { throw UserSessionError.missingCurrentSession }
        let client = session.client
        let catalog = MediaCatalogClient(reader: client, userID: session.user.id)
        let parentID: String?
        let favorites: Bool
        let types: [BaseItemKind]
        switch self {
        case .favorites:
            parentID = nil
            favorites = true
            types = BaseItemKind.supportedCases
        case let .userView(item):
            parentID = item.collectionType == .livetv ? nil : item.id
            favorites = false
            types = item.collectionType == .livetv ? [.tvProgram, .liveTvProgram] : BaseItemKind.supportedCases
        }
        let page = try await catalog.page(
            .artworkSample(parentID: parentID, itemTypes: types, favorites: favorites),
            at: CatalogPageRequest(offset: 0, limit: 3)
        )
        try Task.checkCancellation()
        guard manager.currentSession === session, session.client === client else { throw CancellationError() }
        return page.items.flatMap { $0.imageSources(for: .landscape, size: .custom(width: 200)) }
    }
}
