//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation
import JellyfinAPI

/// Metadata facts have no account, storage or presentation dependency.
public struct ItemMetadataFacts: Sendable {
    private let item: BaseItemDto
    public init(_ item: BaseItemDto) {
        self.item = item
    }

    public var birthday: Date? {
        item.type == .person ? item.premiereDate : nil
    }

    public var birthplace: String? {
        item.type == .person ? item.productionLocations?.first { !$0.isEmpty } : nil
    }

    public var deathday: Date? {
        item.type == .person ? item.endDate : nil
    }

    public var hasExternalLinks: Bool {
        !(item.externalURLs ?? []).isEmpty
    }

    public var hasRatings: Bool {
        item.criticRating != nil || item.communityRating != nil
    }

    public var hasComponents: Bool {
        switch item.type {
        case .audio, .audioBook, .book, .boxSet, .channelFolderItem, .collectionFolder, .episode, .manualPlaylistsFolder, .movie,
             .liveTvProgram, .musicAlbum, .musicArtist, .musicVideo, .playlist, .playlistsFolder, .program, .recording, .season,
             .series, .trailer, .tvProgram, .video: true
        default: false
        }
    }
}

/// Client eligibility only. Jellyfin remains authoritative for every mutation.
public struct ItemMetadataPermissions: Sendable, Equatable {
    public let canDownload: Bool
    public let canEditMetadata: Bool
    public let canEditLyrics: Bool
    public let canEditSubtitles: Bool
}

public extension ItemMetadataPolicy {
    static func permissions(for item: BaseItemDto, policy: UserPolicy?) -> ItemMetadataPermissions {
        guard let policy else {
            return .init(canDownload: false, canEditMetadata: false, canEditLyrics: false, canEditSubtitles: false)
        }
        let administrator = policy.isAdministrator == true
        let metadata: Bool = switch item.type {
        case .playlist: item.canDelete == true
        case .boxSet: policy.enableCollectionManagement || administrator
        default: administrator
        }
        let subtitles: Bool = switch item.type {
        case .episode, .movie, .musicVideo, .trailer, .video: policy.enableSubtitleManagement || administrator
        default: false
        }
        return .init(
            canDownload: policy.enableContentDownloading == true && item.canDownload == true,
            canEditMetadata: metadata,
            canEditLyrics: item.type == .audio && (policy.enableLyricManagement || administrator),
            canEditSubtitles: subtitles
        )
    }

    static func isCrew(_ person: BaseItemPerson) -> Bool {
        person.type == .director || person.type == .writer || person.type == .producer
    }

    /// Preserve order, actor duplicates, nil IDs and distinct nonempty crew roles.
    static func mergedPeople(in item: BaseItemDto) -> [BaseItemPerson]? {
        guard let people = item.people else { return nil }
        let crew = Dictionary(grouping: people.filter(isCrew), by: \.id)
        var seen: Set<String> = []
        return people.compactMap { person in
            guard isCrew(person), let id = person.id, let credits = crew[id], credits.count > 1 else { return person }
            guard seen.insert(id).inserted else { return nil }
            var seenRoles: Set<String> = []
            let roles = credits.compactMap(\.role).filter { !$0.isEmpty && seenRoles.insert($0).inserted }.joined(separator: " / ")
            var person = person
            person.role = roles.isEmpty ? nil : roles
            return person
        }
    }

    /// Keep the first actor role and the final parenthesized suffix when valid.
    /// Trim only spaces to preserve the original handling of tabs and newlines.
    static func displayRole(for person: BaseItemPerson) -> String? {
        guard let role = person.role else { return nil }
        guard !isCrew(person) else { return role }
        let split = role.split(separator: "/")
        guard split.count > 1, let first = split.first, let last = split.last else { return role }
        let spaces = CharacterSet(charactersIn: " ")
        var result = first.trimmingCharacters(in: spaces)
        let finalRole = last.trimmingCharacters(in: spaces)
        if let open = finalRole.lastIndex(of: "("), let close = finalRole.lastIndex(of: ")"), open <= close {
            result.append(" \(finalRole[open ... close])")
        }
        return result
    }
}
