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
import SwiftfinPaging

@MainActor
@Stateful
final class ContentGroupViewModel<Provider: ContentGroupProvider>: ViewModel {

    @CasePathable
    enum Action {
        case refresh

        var transition: Transition {
            .to(.refreshing, then: .content)
                .whenBackground(.refreshing)
        }
    }

    enum BackgroundState {
        case refreshing
    }

    enum State {
        case content
        case error
        case initial
        case refreshing
    }

    @Published
    private(set) var groups: [any ContentGroup] = []

    private let refreshCoordinator = ContentRefreshCoordinator<any ContentGroup>()

    var provider: Provider

    init(provider: Provider) {
        self.provider = provider
        super.init()

        Publishers.Merge(
            Notifications[.itemUserDataDidChange].publisher.map { _ in () },
            Notifications[.itemMetadataDidChange].publisher.map { _ in () }
        )
        .sink { [weak self] _ in
            self?.refreshCoordinator.markChanged()
        }
        .store(in: &cancellables)
    }

    func refreshIfNeeded(
        sinceLastDisappear interval: TimeInterval,
        staleThreshold: TimeInterval = 60
    ) {
        guard refreshCoordinator.shouldRefresh(sinceLastDisappear: interval, staleThreshold: staleThreshold) else { return }

        background.refresh()
    }

    func refreshIfPendingChanges() {
        guard refreshCoordinator.hasPendingChanges else { return }

        refresh()
    }

    @Function(\Action.Cases.refresh)
    private func _refresh() async throws {
        let inBackground = StateTask.isBackground
        if !inBackground {
            groups = []
        }
        let updated = try await refreshCoordinator.refresh(
            inBackground: inBackground,
            makeGroups: { [weak self] in
                guard let self else { throw CancellationError() }
                return try await provider.makeGroups(environment: provider.environment)
            },
            operations: { groups, background in
                groups.map { group in
                    let model = group.viewModel
                    return ContentRefreshOperation(identity: ObjectIdentifier(model as AnyObject)) {
                        if background {
                            await model.background.refresh()
                        } else {
                            await model.refresh()
                        }
                    }
                }
            },
            shouldResolve: { $0._shouldBeResolved }
        )
        try Task.checkCancellation()
        groups = updated
    }
}
