//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation
import JellyfinAPI
import SwiftfinItemMetadata
import Testing

struct ItemMetadataProjectionContracts {
    private func policy(admin: Bool? = nil) -> UserPolicy {
        .init(authenticationProviderID: "synthetic", isAdministrator: admin, passwordResetProviderID: "synthetic")
    }

    @Test
    func `absent policy denies all and playlist metadata needs deletion even for admin`() {
        var item = BaseItemDto(type: .playlist)
        let denied = ItemMetadataPolicy.permissions(for: item, policy: nil)
        #expect(!denied.canDownload && !denied.canEditMetadata && !denied.canEditLyrics && !denied.canEditSubtitles)
        #expect(!ItemMetadataPolicy.permissions(for: item, policy: policy(admin: true)).canEditMetadata)
        item.canDelete = true
        #expect(ItemMetadataPolicy.permissions(for: item, policy: policy()).canEditMetadata)
        item.type = .boxSet
        var p = policy()
        p.enableCollectionManagement = true
        #expect(ItemMetadataPolicy.permissions(for: item, policy: p).canEditMetadata)
        item.type = .movie
        #expect(!ItemMetadataPolicy.permissions(for: item, policy: p).canEditMetadata)
    }

    @Test
    func `specific management grants do not grant unrelated edits or downloads`() {
        var p = policy()
        p.enableLyricManagement = true
        p.enableSubtitleManagement = true
        p.enableContentDownloading = true
        var item = BaseItemDto(type: .audio)
        #expect(ItemMetadataPolicy.permissions(for: item, policy: p).canEditLyrics)
        #expect(!ItemMetadataPolicy.permissions(for: item, policy: p).canEditSubtitles)
        #expect(!ItemMetadataPolicy.permissions(for: item, policy: p).canDownload)
        item.type = .episode
        item.canDownload = true
        let rights = ItemMetadataPolicy.permissions(for: item, policy: p)
        #expect(!rights.canEditLyrics && rights.canEditSubtitles && rights.canDownload && !rights.canEditMetadata)
    }

    @Test
    func `malformed reversed parentheses never construct an invalid range`() {
        let malformed = ["First / Last) (", "First / Last (", "First / Last)", "First / Last) (("]
        for role in malformed {
            #expect(ItemMetadataPolicy.displayRole(for: .init(role: role, type: .actor)) == "First")
        }
        #expect(ItemMetadataPolicy.displayRole(for: .init(role: " First / Last (voice) ", type: .actor)) == "First (voice)")
        #expect(ItemMetadataPolicy.displayRole(for: .init(role: "\tFirst / Last (角色)", type: .actor)) == "\tFirst (角色)")
        #expect(ItemMetadataPolicy.displayRole(for: .init(role: malformed[0], type: .writer)) == malformed[0])
    }

    @Test
    func `crew merge retains first identity actor duplicates nil IDs and role order`() {
        let people: [BaseItemPerson] = [
            .init(id: "same", name: "Actor", role: "A", type: .actor),
            .init(id: "same", name: "Crew", role: "D", type: .director),
            .init(id: "same", role: "W", type: .writer), .init(id: "same", role: "D", type: .producer),
            .init(id: "same", role: "B", type: .actor), .init(role: "X", type: .director), .init(role: "Y", type: .writer)
        ]
        let result = ItemMetadataPolicy.mergedPeople(in: .init(people: people))
        #expect(result?.map(\.role) == ["A", "D / W", "B", "X", "Y"])
        #expect(result?[1].name == "Crew" && result?[1].type == .director)
        #expect(ItemMetadataPolicy.mergedPeople(in: .init()) == nil)
        #expect(ItemMetadataPolicy.mergedPeople(in: .init(people: [])) == [])
    }

    @Test
    func `person facts retain whitespace location and zero ratings while excluding other types`() {
        var item = BaseItemDto(
            endDate: .init(timeIntervalSince1970: 20),
            premiereDate: .init(timeIntervalSince1970: 10),
            productionLocations: ["", " ", "City"],
            type: .person
        )
        item.criticRating = 0
        let facts = ItemMetadataFacts(item)
        #expect(facts.birthday == item.premiereDate && facts.deathday == item.endDate && facts.birthplace == " ")
        #expect(facts.hasRatings && !facts.hasExternalLinks && !facts.hasComponents)
        item.type = .movie
        #expect(ItemMetadataFacts(item).birthday == nil && ItemMetadataFacts(item).hasComponents)
    }
}
