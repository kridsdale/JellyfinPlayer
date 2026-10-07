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
import SwiftfinServerOperations
import SwiftfinTime
import Testing

private struct OriginalOverlaySession: Decodable { let deviceID: String?
    let itemID: String?
}

private struct OriginalOverlayFixture: Decodable {
    let originalCommit: String
    let sourceHashes: [String: String]
    let memberHashes: [String: String]
    let vectors: [[OriginalOverlaySession]]
    let devices: [String?]
    let items: [String]
    let selections: [[Int?]]
    let ageInputs: [[Double]]
    let recent: [Bool]
    let delayInputs: [[Double]]
    let delays: [Double]
}

struct OverlayOriginalContracts {
    private func fixture() throws -> OriginalOverlayFixture {
        let url = try #require(Bundle.module.url(forResource: "overlay-original-eeadc535", withExtension: "json"))
        return try JSONDecoder().decode(OriginalOverlayFixture.self, from: Data(contentsOf: url))
    }

    @Test
    func `original overlay source and expression provenance`() throws {
        let original = try fixture()
        #expect(original.originalCommit == "eeadc5352071270d661ad77a253b1dc76468bec1")
        #expect(original.sourceHashes == [
            "Shared/Objects/MediaPlayerManager/Supplements/EPGSupplement.swift": "4a8608c37901db63c5f64fe8fd285223acd49c4e85fa56d427d4fbb59f45bb89",
            "Shared/Objects/MediaPlayerManager/Supplements/MediaInfoSupplement.swift": "97008675dfa5e87536133f55db37b68fa11c9793cf22d4e90c07bb51ef70181b",
            "Shared/Objects/MediaPlayerManager/Supplements/PlaybackInformationSupplement.swift": "99be087cc38ec34c361060ef039e2252f469db2a9ff3cab9cec560a718dea582"
        ])
        #expect(original.memberHashes == [
            "recentAge": "74db3237f0dafd570c669faa4c6ccc34b76a215db938bcb1f8b0cd757c3b11ab",
            "refreshDelay": "9dcac679bd1c4fb3f6b1e01a54c7f80a17962c77f81d5366e49bbed5cbaf132b",
            "sessionSelection": "78fed2aaa363973ec654be28d9302154884777860380ce155b09ad80b27f8214"
        ])
        #expect(original.selections.count == 820 && original.selections.reduce(0) { $0 + $1.count } == 4920)
    }

    @Test
    func `all original ordered device and item session preferences match`() throws {
        let original = try fixture()
        #expect(original.vectors.count == original.selections.count)
        for (vector, expected) in zip(original.vectors, original.selections) {
            let values = vector.enumerated().map { index, value in
                SessionInfoDto(deviceID: value.deviceID, id: String(index), nowPlayingItem: value.itemID.map { .init(id: $0) })
            }
            let actual = original.devices.flatMap { device in original.items.map { item in
                ServerOperationsPolicy.playbackSession(in: values, deviceID: device, itemID: item)?.id.flatMap(Int.init)
            } }
            #expect(actual == expected)
        }
    }

    @Test
    func `all original strict guide age decisions match`() throws {
        let original = try fixture()
        #expect(original.ageInputs.count == original.recent.count)
        for (input, expected) in zip(original.ageInputs, original.recent) {
            #expect(Date(timeIntervalSince1970: input[0]).isRecent(
                with: .seconds(input[2]),
                comparedTo: .init(timeIntervalSince1970: input[1])
            ) == expected)
        }
    }

    @Test
    func `all original program end grace and minimum delays match`() throws {
        let original = try fixture()
        #expect(original.delayInputs.count == original.delays.count)
        for (input, expected) in zip(original.delayInputs, original.delays) {
            #expect(try ProgramMetadataRefresh.delay(
                after: .init(timeIntervalSince1970: input[1]),
                comparedTo: .init(timeIntervalSince1970: input[0])
            ) == .seconds(expected))
        }
    }
}
