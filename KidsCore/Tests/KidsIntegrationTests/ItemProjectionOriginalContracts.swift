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
import SwiftfinMediaCatalog
import SwiftfinMediaTracks
import SwiftfinTime
import SwiftfinUserMediaState
import Testing

struct ItemProjectionOriginalContracts {
    private func fixture() throws -> ProjectionFixture {
        let url = try #require(Bundle.module.url(forResource: "item-projections-original-8b75baa1", withExtension: "json"))
        return try JSONDecoder().decode(ProjectionFixture.self, from: Data(contentsOf: url))
    }

    @Test
    func `original capture provenance and complete scenario cardinality`() throws {
        let original = try fixture()
        #expect(original.originalCommit == "8b75baa13bd3d4b4d2f07592f97e32e74e5ec660")
        #expect(original
            .sourceHashes["Shared/Extensions/JellyfinAPI/BaseItemDto/BaseItemDto.swift"] ==
            "7fa4a3b5009fd5828456d9bdac64155702de9751d623b0024de7e7e4c16ac3d4")
        #expect(original
            .sourceHashes["Shared/Extensions/JellyfinAPI/BaseItemDto/BaseItemDto+Permissions.swift"] ==
            "64056232848b514b2962bb00eb56d3dfac8b507ab097d7f74ea175dd5165fb80")
        #expect(original
            .sourceHashes["Shared/Extensions/JellyfinAPI/BaseItemPerson/BaseItemPerson.swift"] ==
            "e5e8a72d32182d7c93256b95b74916523df059af153af4d7117f14b49f80b6f2")
        #expect(original.memberHashes.count == 34 && original.permissionMasks.count == 18810 && original.kindMasks.count == 152)
        #expect(original.kindValues == ProjectionInputs.kinds.map { $0?.rawValue })
    }

    @Test
    func `all original kinds missing states and control eligibility`() throws {
        var masks: [Int] = []
        for kind in ProjectionInputs.kinds {
            var item = ProjectionInputs.basic(kind)
            let state = CatalogItemState(item, at: ProjectionInputs.now)
            let metadata = ItemMetadataFacts(item)
            let capabilities = UserMediaStatePolicy.capabilities(for: kind)
            masks.append(ProjectionInputs.mask([
                state.isPlayable,
                capabilities.canBeFavorited,
                capabilities.canBePlayed,
                metadata.hasComponents,
                metadata.hasRatings,
                metadata.hasExternalLinks,
                state.presentsPlayButton(permitted: true)
            ]))
            for flag in ProjectionInputs.flags {
                item.locationType = flag == true ? .virtual : nil
                let state = CatalogItemState(item, at: ProjectionInputs.now)
                masks.append(ProjectionInputs.mask([state.isMissing, state.isPlayable]))
            }
        }
        #expect(try masks == fixture().kindMasks)
    }

    @Test
    func `all original policies optional flags and item mutation permissions`() throws {
        var masks: [Int] = []
        func append(_ item: BaseItemDto, _ policy: UserPolicy?) {
            let rights = ItemMetadataPolicy.permissions(for: item, policy: policy)
            masks.append(ProjectionInputs.mask([
                rights.canDownload,
                rights.canEditMetadata,
                rights.canEditLyrics,
                rights.canEditSubtitles,
                CatalogItemState(item, at: ProjectionInputs.now).presentsPlayButton(permitted: policy?.enableMediaPlayback == true)
            ]))
        }
        for kind in ProjectionInputs.kinds {
            for group in 0 ..<
                6
            {
                for admin in ProjectionInputs
                    .flags
                {
                    for flag in ProjectionInputs.flags {
                        for download in ProjectionInputs.flags {
                            for deletion in ProjectionInputs.flags {
                                var item = ProjectionInputs.basic(kind)
                                item.canDownload = download
                                item.canDelete = deletion
                                append(item, ProjectionInputs.policy(admin: admin, flag: flag, group: group))
                            }
                        }
                    }
                }
            }
            for download in ProjectionInputs.flags {
                for deletion in ProjectionInputs.flags {
                    var item = ProjectionInputs.basic(kind)
                    item.canDownload = download
                    item.canDelete = deletion
                    append(item, nil)
                }
            }
        }
        #expect(try masks == fixture().permissionMasks)
    }

    @Test
    func `original signed ticks invalid spans nested programs and explicit dates`() throws {
        let original = try fixture()
        let numbers = original.timeInputs.map { input in
            let state = CatalogItemState(input.item, at: ProjectionInputs.now)
            return [
                state.runtime?.seconds.description,
                state.startSeconds?.seconds.description,
                state.programDuration?.description,
                state.programProgress?.description,
                state.programProgress(relativeTo: Date(timeIntervalSince1970: 125))?.description,
                state.progressPercentage?.description
            ]
        }
        let masks = original.timeInputs.map { input in
            let state = CatalogItemState(input.item, at: ProjectionInputs.now)
            return ProjectionInputs.mask([
                state.isLiveStream,
                state.isAiring,
                state.isUnaired,
                state.hasAired,
                state.isRecording,
                state.isPlayable
            ])
        }
        #expect(numbers == original.timeNumbers && masks == original.timeMasks)
    }

    @Test
    func `original valid role strings and stable crew credits`() throws {
        let original = try fixture()
        #expect(original.roleInputs.map { ItemMetadataPolicy.displayRole(for: $0.item) } == original.roleOutputs)
        let crews = original.crewInputs.map { people -> [ProjectionPersonInput]? in
            ItemMetadataPolicy.mergedPeople(in: .init(people: people?.map(\.item)))?.map(ProjectionPersonInput.init)
        }
        #expect(crews == original.crewOutputs)
    }

    @Test
    func `original person facts and parent identity for every kind`() throws {
        let facts = ProjectionInputs.kinds.map { kind -> [String?] in
            let item = ProjectionInputs.basic(kind)
            let metadata = ItemMetadataFacts(item)
            let state = CatalogItemState(item, at: ProjectionInputs.now)
            return [
                metadata.birthday?.timeIntervalSince1970.description,
                metadata.deathday?.timeIntervalSince1970.description,
                metadata.birthplace,
                state.parentTitle,
                state.parentRootID
            ]
        }
        #expect(try facts == fixture().personFacts)
    }

    @Test
    func `original raw stream classification includes every SDK kind`() throws {
        let streams = ProjectionInputs.streams()
        let indices = [MediaStreamType.audio, .subtitle, .video]
            .map { MediaStreamKindPolicy.streams(in: streams, matching: $0).map(\.index) }
        #expect(try indices == fixture().streamIndices)
    }
}
