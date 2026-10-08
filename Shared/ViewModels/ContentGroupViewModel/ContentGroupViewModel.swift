//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import CasePaths
import Combine
import Foundation
import JellyfinAPI
import StatefulMacros
import SwiftfinAsyncStreams
import SwiftfinPaging

@MainActor
@Stateful
final class ContentGroupViewModel<Provider: ContentGroupProvider>: ViewModel {

    @CasePathable
    enum Action {
        case refresh
        case refreshScoped(Request)

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

    struct Request: Sendable {
        let makeGroups: @MainActor @Sendable () async throws -> [any ContentGroup]
        let validate: ContentRefreshOperation.Checkpoint
    }

    private func request(validate: @escaping ContentRefreshOperation.Checkpoint = {}) -> Request {
        let provider = provider
        let environment = provider.environment
        return Request(makeGroups: { try await provider.makeGroups(environment: environment) }, validate: validate)
    }

    func invalidateRefresh() {
        refreshCoordinator.cancel()
        groups = []
    }

    func refreshForScope(validate: @escaping ContentRefreshOperation.Checkpoint) async {
        guard (try? validate()) != nil else { return }
        await refreshScoped(request(validate: validate))
    }

    @Function(\Action.Cases.refresh)
    private func _refresh() async throws {
        try await perform(request())
    }

    @Function(\Action.Cases.refreshScoped)
    private func _refreshScoped(_ request: Request) async throws {
        try await perform(request)
    }

    private func perform(_ request: Request) async throws {
        try request.validate()
        let inBackground = StateTask.isBackground
        if !inBackground {
            groups = []
        }
        try request.validate()
        let updated = try await refreshCoordinator.refresh(
            inBackground: inBackground,
            validate: request.validate,
            makeGroups: request.makeGroups,
            operations: { groups, background in
                groups.map { group in
                    let model = group.viewModel
                    return ContentRefreshOperation(identity: ObjectIdentifier(model as AnyObject), scopedRefresh: { validate in
                        try validate()
                        if let scoped = model as? any WithRefreshScope {
                            try scoped.bindRefreshScope(validate)
                        }
                        try validate()
                        if background {
                            await model.background.refresh()
                        } else {
                            await model.refresh()
                        }
                        try validate()
                    })
                }
            },
            shouldResolve: { $0._shouldBeResolved }
        )
        try request.validate()
        groups = updated
    }
}
