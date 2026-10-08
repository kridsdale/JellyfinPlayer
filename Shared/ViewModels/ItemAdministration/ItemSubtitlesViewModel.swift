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
import JellyfinAPI
import StatefulMacros
import SwiftfinAsyncStreams
import SwiftfinItemMetadata
import SwiftfinLocalization
import SwiftfinPlaybackProfiles
import SwiftfinUIState

@MainActor
@Stateful
final class ItemSubtitlesViewModel: ViewModel {
    struct SearchRequest: Sendable { let query: MetadataSubtitleQuery
        let validate: AsyncOperationGate.Checkpoint
    }

    @CasePathable
    enum Action {
        case performSearch(SearchRequest)
        case performRefresh(Request)
        case performSet(Request, Set<String>)
        case performDelete(Request, Set<MediaStream>)
        case performUpload(Request, URL, String, Bool, Bool)
        var transition: Transition {
            switch self {
            case .performRefresh: .to(.initial, then: .content)
            case .performSearch: .background(.searching)
            case .performSet, .performUpload, .performDelete: .background(.updating)
            }
        }
    }

    enum BackgroundState { case updating, searching }
    enum Event { case deleted, uploaded }
    enum State { case initial, content, error }
    @CommittedPublished
    private(set) var internalSubtitles: [MediaStream] {
        didSet { objectWillChange.send() }
    }

    @CommittedPublished
    private(set) var externalSubtitles: [MediaStream] {
        didSet { objectWillChange.send() }
    }

    @CommittedPublished
    private(set) var results: [RemoteSubtitleInfo] = [] {
        didSet { objectWillChange.send() }
    }

    @Published
    var language: String? = Locale.current.language.languageCode?.identifier(.alpha3)
    let item: BaseItemDto
    private let searches = AsyncOperationGate()
    private let query = CurrentValueSubject<Bool, Never>(false)
    struct Request: Sendable { let validate: AsyncOperationGate.Checkpoint }
    private let editor: ItemMetadataEditor?
    private let operations = AsyncOperationGate()

    private func request(using gate: AsyncOperationGate? = nil) -> Request? {
        guard let editor, item.id == editor.itemID, !Task.isCancelled,
              (try? editor.checkBinding()) != nil else { return nil }
        let check = (gate ?? operations).begin()
        return Request(validate: { [weak self] in
            try check()
            try editor.checkBinding()
            guard self?.item.id == editor.itemID else { throw CancellationError() }
            try check()
        })
    }

    init(item: BaseItemDto) {
        self.item = item
        editor = try? Container.shared.currentUserSession()?.itemMetadata.makeEditor(itemID: item.id ?? "")
        let subtitles = ItemMetadataPolicy.subtitles(item)
        internalSubtitles = subtitles.internalStreams
        externalSubtitles = subtitles.externalStreams
        super.init()
        $language.combineLatest(query)
            .removeDuplicates(by: { $0.0 == $1.0 && $0.1 == $1.1 })
            .compactMap { [weak self] language, perfectMatch -> SearchRequest? in
                guard let self, let request = request(using: searches) else { return nil }
                return SearchRequest(query: .init(language: language, perfectMatch: perfectMatch), validate: request.validate)
            }
            .debounce(for: 0.5, scheduler: RunLoop.main)
            .sink { [weak self] request in
                guard (try? request.validate()) != nil else { return }
                self?.performSearch(request)
            }
            .store(in: &cancellables)
    }

    func search(isPerfectMatch: Bool) {
        guard !Task.isCancelled, (try? editor?.checkBinding()) != nil else { return }
        query.send(isPerfectMatch)
    }

    func refresh() {
        if let request = request() {
            performRefresh(request)
        }
    }

    func set(_ ids: Set<String>) {
        if let request = request() {
            performSet(request, ids)
        }
    }

    func delete(_ streams: Set<MediaStream>) {
        if let request = request() {
            performDelete(request, streams)
        }
    }

    func upload(file: URL, isForced: Bool, isHearingImpaired: Bool) {
        guard let language, !language.isEmpty, let request = request() else { return }
        performUpload(request, file, language, isForced, isHearingImpaired)
    }

    private func publish(_ updated: BaseItemDto, request: Request, notify: Bool, event: _Event? = nil) throws {
        try request.validate()
        let subtitles = ItemMetadataPolicy.subtitles(updated)
        internalSubtitles = subtitles.internalStreams
        try request.validate()
        externalSubtitles = subtitles.externalStreams
        try request.validate()
        if notify {
            Notifications[.itemMetadataDidChange].post(updated)
        }
        try request.validate()
        if let event {
            events.send(event)
        }
    }

    @Function(\Action.Cases.performRefresh)
    private func _performRefresh(_ request: Request) async throws {
        guard let editor else { throw CancellationError() }
        try await publish(editor.item(validate: request.validate), request: request, notify: false)
    }

    @Function(\Action.Cases.performSearch)
    private func _performSearch(_ request: SearchRequest) async throws {
        guard let editor else { throw CancellationError() }
        let updated = try await editor.searchSubtitles(request.query, validate: request.validate)
        try request.validate()
        results = updated
    }

    @Function(\Action.Cases.performSet)
    private func _performSet(_ request: Request, _ ids: Set<String>) async throws {
        guard let editor else { throw CancellationError() }
        try await publish(
            editor.editSubtitles(.download(ids), validate: request.validate),
            request: request,
            notify: true,
            event: .uploaded
        )
    }

    @Function(\Action.Cases.performDelete)
    private func _performDelete(_ request: Request, _ streams: Set<MediaStream>) async throws {
        guard let editor else { throw CancellationError() }
        do {
            try await publish(
                editor.editSubtitles(.delete(Set(streams.compactMap(\.index))), validate: request.validate),
                request: request,
                notify: true,
                event: .deleted
            )
        } catch let failure as MetadataSubtitleDeletionFailure {
            try request.validate()
            throw ErrorMessage(L10n.failedDeletionAtIndexError(failure.index, failure.underlying))
        }
    }

    @Function(\Action.Cases.performUpload)
    private func _performUpload(_ request: Request, _ file: URL, _ language: String, _ forced: Bool, _ hearingImpaired: Bool) async throws {
        guard let editor else { throw CancellationError() }
        try request.validate()
        guard file.isFileURL, let format = SubtitleFormat(url: file) else { throw ErrorMessage(L10n.invalidFormat) }
        let data = try Data(contentsOf: file)
        try request.validate()
        let updated = try await editor.editSubtitles(.upload(
            data: data,
            format: format.fileExtension,
            language: language,
            forced: forced,
            hearingImpaired: hearingImpaired
        ), validate: request.validate)
        try publish(updated, request: request, notify: true, event: .uploaded)
    }
}
