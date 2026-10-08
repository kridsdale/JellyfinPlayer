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
import IdentifiedCollections
import JellyfinAPI
import StatefulMacros
import SwiftfinAsyncStreams
import SwiftfinMediaCatalog
import SwiftfinTime
import SwiftfinUIState

@MainActor
@Stateful
final class EPGViewModel: ViewModel {
    struct Request: Sendable {
        let start: Date
        let end: Date
        let previous: GuideSnapshot
        let validate: AsyncOperationGate.Checkpoint
    }

    @CasePathable
    enum Action {
        case runRefresh(Request)
        case runPage(Request)
        var transition: Transition {
            switch self {
            case .runRefresh: .to(.refreshing, then: .content).onRepeat(.cancel)
            case .runPage: .background(.gettingNextPage)
            }
        }
    }

    enum BackgroundState { case gettingNextPage }
    enum State {
        case content
        case error
        case initial
        case refreshing
    }

    private struct Display: Equatable {
        let source: GuideSnapshot
        let channels: IdentifiedArrayOf<BaseItemDto>
        init(_ source: GuideSnapshot) {
            self.source = source
            channels = IdentifiedArray(source.channels, uniquingIDsWith: { existing, _ in existing })
        }
    }

    @CommittedPublished
    private var display: Display {
        didSet { objectWillChange.send() }
    }

    @CommittedPublished
    private(set) var now: Date {
        didSet { objectWillChange.send() }
    }

    var channels: IdentifiedArrayOf<BaseItemDto> {
        display.channels
    }

    var programs: [String: [ProgramBlock]] {
        display.source.programs
    }

    var programsRevision: Int {
        display.source.revision
    }

    var startDate: Date {
        display.source.startDate
    }

    var availableDates: [Date] {
        timeline.availableDates(at: .now)
    }

    var endDate: Date {
        timeline.endDate(startingAt: startDate)
    }

    private let minimumDuration: Duration
    private var timeline: GuideTimeline {
        .init(minimumInterval: minimumDuration.seconds)
    }

    private var catalog: MediaCatalogClient?
    private let refreshes = AsyncOperationGate()
    private let pages = AsyncOperationGate()

    init(minimumDuration: Duration = .hours(12)) {
        self.minimumDuration = minimumDuration
        let date = Date.now
        now = date
        display = .init(.init(startDate: GuideTimeline(minimumInterval: minimumDuration.seconds).defaultStartDate(at: date)))
        super.init()
        catalog = try? requireMediaCatalog()
        Timer.publish(every: 60, on: .main, in: .common).autoconnect().sink { [weak self] date in
            Task { @MainActor in
                guard let self, let catalog = self.catalog, (try? catalog.checkBinding()) != nil else { return }
                self.now = date
                guard (try? catalog.checkBinding()) != nil else { return }
                if self.timeline.needsRebase(start: self.startDate, now: date), self.state == .content {
                    self.refresh(startDate: nil)
                }
            }
        }.store(in: &cancellables)
    }

    private func request(start: Date, using gate: AsyncOperationGate) -> Request? {
        guard let catalog, (try? catalog.checkBinding()) != nil else { return nil }
        let receipt = gate.begin()
        return .init(
            start: start,
            end: timeline.endDate(startingAt: start),
            previous: display.source,
            validate: { [weak self] in
                try receipt()
                try catalog.checkBinding()
                guard self != nil else { throw CancellationError() }
                try receipt()
            }
        )
    }

    func refresh(startDate requested: Date?) {
        guard let request = request(start: requested ?? timeline.refreshedStartDate(startDate, now: .now), using: refreshes) else { return }
        pages.cancel()
        runRefresh(request)
    }

    func refresh(startDate requested: Date?) async {
        guard let request = request(start: requested ?? timeline.refreshedStartDate(startDate, now: .now), using: refreshes) else { return }
        pages.cancel()
        await runRefresh(request)
    }

    func setDate(date: Date) {
        let start = timeline.selectedStartDate(date, now: .now)
        guard start != startDate else { return }
        refresh(startDate: start)
    }

    func getNextPage() {
        guard state == .content, display.source.hasNextPage, !background.is(.gettingNextPage),
              let request = request(start: startDate, using: pages) else { return }
        runPage(request)
    }

    @Function(\Action.Cases.runRefresh)
    private func _runRefresh(_ request: Request) async throws {
        do {
            try request.validate()
            guard let catalog else { throw CancellationError() }
            let page = try await catalog.guidePage(
                offset: 0,
                limit: defaultPagingLibraryPageSize,
                startDate: request.start,
                endDate: request.end,
                validate: request.validate
            )
            try request.validate()
            display = .init(display.source.applying(page, startDate: request.start, replacing: true))
            try request.validate()
        } catch { try request.validate()
            throw error
        }
    }

    @Function(\Action.Cases.runPage)
    private func _runPage(_ request: Request) async throws {
        func check() throws {
            try request.validate()
            guard display.source == request.previous else { throw CancellationError() }
        }
        do {
            try check()
            guard let catalog else { throw CancellationError() }
            let page = try await catalog.guidePage(
                offset: request.previous.nextOffset,
                limit: defaultPagingLibraryPageSize,
                startDate: request.start,
                endDate: request.end,
                excluding: Set(request.previous.channels.compactMap(\.id)),
                validate: check
            )
            try check()
            display = .init(request.previous.applying(page, startDate: request.start, replacing: false))
            try request.validate()
        } catch { try request.validate()
            throw error
        }
    }
}
