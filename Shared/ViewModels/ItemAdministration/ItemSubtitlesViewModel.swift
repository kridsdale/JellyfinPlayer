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
import SwiftfinAsyncStreams
import SwiftfinCollections
import SwiftfinItemMetadata
import SwiftfinLocalization
import SwiftfinPlaybackProfiles

@MainActor
@Stateful
final class ItemSubtitlesViewModel: ViewModel {

    @CasePathable
    enum Action {
        case _actuallySearch(isPerfectMatch: Bool)
        case delete(Set<MediaStream>)
        case refresh
        case search(isPerfectMatch: Bool)
        case set(Set<String>)
        case upload(file: URL, isForced: Bool, isHearingImpaired: Bool)

        var transition: Transition {
            switch self {
            case .refresh:
                .to(.initial, then: .content)
            case ._actuallySearch, .search:
                .background(.searching)
            case .set, .upload, .delete:
                .background(.updating)
            }
        }
    }

    enum BackgroundState {
        case updating
        case searching
    }

    enum Event {
        case deleted
        case uploaded
    }

    enum State {
        case initial
        case content
        case error
    }

    @Published
    private(set) var internalSubtitles: [MediaStream]
    @Published
    private(set) var externalSubtitles: [MediaStream]
    @Published
    private(set) var results: [RemoteSubtitleInfo] = []

    /// Default to user's language
    @Published
    var language: String? = Locale.current.language.languageCode?.identifier(.alpha3)

    let item: BaseItemDto

    private var query: CurrentValueSubject<Bool, Never> = .init(false)

    init(item: BaseItemDto) {
        self.item = item

        let subtitles = ItemMetadataPolicy.subtitles(item)
        internalSubtitles = subtitles.internalStreams
        externalSubtitles = subtitles.externalStreams

        super.init()

        $language
            .combineLatest(query)
            .debounce(for: 0.5, scheduler: RunLoop.main)
            .removeDuplicates(by: { $0.0 == $1.0 && $0.1 == $1.1 })
            .sink { [weak self] _, isPerfectMatch in
                self?._actuallySearch(isPerfectMatch: isPerfectMatch)
            }
            .store(in: &cancellables)
    }

    @Function(\Action.Cases.refresh)
    private func _refresh() async throws {
        try await refreshItem(sendNotification: false)
    }

    private func refreshItem(sendNotification: Bool = false, metadata: ItemMetadataClient? = nil) async throws {
        guard let itemID = item.id else { throw ErrorMessage(L10n.unknownError) }
        let reader = try metadata ?? requireItemMetadata()
        let updated = try await reader.item(id: itemID)
        let subtitles = ItemMetadataPolicy.subtitles(updated)
        internalSubtitles = subtitles.internalStreams
        externalSubtitles = subtitles.externalStreams
        if sendNotification {
            Notifications[.itemMetadataDidChange].post(updated)
        }
    }

    @Function(\Action.Cases.search)
    private func _search(_ isPerfectMatch: Bool) async throws {
        query.send(isPerfectMatch)

        await cancel()
    }

    @Function(\Action.Cases._actuallySearch)
    private func __actuallySearch(_ isPerfectMatch: Bool) async throws {
        guard let itemID = item.id else { throw ErrorMessage(L10n.unknownError) }
        guard let language, language.isNotEmpty else { results = []
            return
        }
        results = try await requireItemMetadata().searchSubtitles(itemID: itemID, language: language, perfectMatch: isPerfectMatch)
    }

    @Function(\Action.Cases.set)
    private func _set(_ subtitles: Set<String>) async throws {
        guard let itemID = item.id else { throw ErrorMessage(L10n.unknownError) }
        let metadata = try requireItemMetadata()
        try await metadata.downloadSubtitles(itemID: itemID, subtitleIDs: subtitles)
        try await refreshItem(sendNotification: true, metadata: metadata)
        events.send(.uploaded)
    }

    @Function(\Action.Cases.upload)
    private func _upload(_ file: URL, _ isForced: Bool, _ isHearingImpaired: Bool) async throws {
        guard let itemID = item.id, let language, language.isNotEmpty else { throw ErrorMessage(L10n.unknownError) }
        guard file.isFileURL, let format = SubtitleFormat(url: file) else { throw ErrorMessage(L10n.invalidFormat) }
        let metadata = try requireItemMetadata()
        let data = try Data(contentsOf: file)
        try await metadata.uploadSubtitle(
            itemID: itemID,
            data: data,
            format: format.fileExtension,
            language: language,
            forced: isForced,
            hearingImpaired: isHearingImpaired
        )
        try await refreshItem(sendNotification: true, metadata: metadata)
        events.send(.uploaded)
    }

    @Function(\Action.Cases.delete)
    private func _delete(_ mediaStreams: Set<MediaStream>) async throws {
        guard let itemID = item.id else { throw ErrorMessage(L10n.unknownError) }
        let metadata = try requireItemMetadata()
        do { try await metadata.deleteSubtitles(itemID: itemID, indices: Set(mediaStreams.compactMap(\.index))) }
        catch let error as MetadataSubtitleDeletionFailure { throw ErrorMessage(L10n.failedDeletionAtIndexError(
            error.index,
            error.underlying
        )) }
        try await refreshItem(sendNotification: true, metadata: metadata)
        events.send(.deleted)
    }
}
