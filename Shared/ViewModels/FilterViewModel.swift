//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Combine
import Foundation
import JellyfinAPI
import OrderedCollections
import SwiftfinCollections
import SwiftfinFilters
import SwiftUI

@MainActor
@Stateful
final class FilterViewModel: ViewModel {

    @CasePathable
    enum Action {
        case cancel
        case getQueryFilters
        case reset(filterType: ItemFilterType?)

        var transition: Transition {
            switch self {
            case .cancel, .reset: .none
            case .getQueryFilters:
                .background(.retrievingQueryFilters)
            }
        }
    }

    enum BackgroundState {
        case retrievingQueryFilters
    }

    @Published
    private(set) var allFilters: ItemFilterCollection = .all
    @Published
    var currentFilters: ItemFilterCollection

    /// Fixed filters, excluded from selection state and reset actions
    let staticFilters: ItemFilterCollection

    private let parent: (any LibraryParent)?

    var hasActiveFilters: Bool {
        staticFilters.union(currentFilters) != staticFilters
    }

    private var itemTypes: [BaseItemKind] {
        staticFilters.itemTypes.isEmpty ?
            parent?.supportedItemTypes ?? BaseItemKind.supportedCases :
            staticFilters.itemTypes
    }

    init(
        parent: (any LibraryParent)? = nil,
        currentFilters: ItemFilterCollection = .default,
        staticFilters: ItemFilterCollection = .default
    ) {
        self.parent = parent
        self.currentFilters = currentFilters
        self.staticFilters = staticFilters

        super.init()
    }

    func isFilterSelected(type: ItemFilterType) -> Bool {
        guard !staticFilters.containsFilters(ofType: type) else { return false }

        return currentFilters.containsFilters(ofType: type)
    }

    @Function(\Action.Cases.reset)
    private func resetCurrentFilters(_ type: ItemFilterType?) async {
        currentFilters.reset(type)
    }

    @Function(\Action.Cases.getQueryFilters)
    private func _getQueryFilters() async throws {
        let filters = try requireQueryFilters()
        let parentID = parent?.id
        let requestedTypes = itemTypes
        let modern = try await filters.modern(parentID: parentID, itemTypes: requestedTypes)
        try filters.checkBinding()
        allFilters = modern.applying(to: allFilters)
        let legacy = try await filters.legacy(parentID: parentID, itemTypes: requestedTypes)
        try filters.checkBinding()
        allFilters = legacy.applying(to: allFilters)
    }
}
