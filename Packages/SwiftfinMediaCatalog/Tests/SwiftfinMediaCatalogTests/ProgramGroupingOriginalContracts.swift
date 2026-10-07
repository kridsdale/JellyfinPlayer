//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation
@testable import SwiftfinMediaCatalog
import Testing

private struct OriginalAiring: Codable, Equatable { let date: Double
    let value: Bool
}

private struct OriginalBlock: Codable, Equatable {
    let channel: String?
    let ids: [String?]
    let start: Double
    let end: Double
    let samples: [ProgramGroupingSample]
    let grouped: Bool
    let airing: [OriginalAiring]
}

private struct OriginalScenario: Codable { let name: String
    let start: Double
    let end: Double
    let samples: [ProgramGroupingSample]
    let expected: [OriginalBlock]
}

private struct OriginalCapture: Codable { let originalCommit: String
    let sourceHashes: [String: String]
    let cases: [OriginalScenario]
}

@Test
func `program grouping matches independently executed original sources`() throws {
    let url = try #require(Bundle.module.url(forResource: "program-grouping-original-3c44f2e5", withExtension: "json"))
    let original = try JSONDecoder().decode(OriginalCapture.self, from: Data(contentsOf: url))
    #expect(original.originalCommit == "3c44f2e5f3f29031af11261bee1b56f253995647" && original.sourceHashes.count == 2)
    #expect(original.cases.count == 9)
    for scenario in original.cases {
        let actual = scenario.samples.map(\.item).programBlocks(
            startDate: Date(timeIntervalSince1970: scenario.start),
            endDate: Date(timeIntervalSince1970: scenario.end)
        ).map { b in
            OriginalBlock(
                channel: b.id.channelID,
                ids: b.id.programIDs,
                start: b.start.timeIntervalSince1970,
                end: b.end.timeIntervalSince1970,
                samples: b.programs.map(ProgramGroupingSample.init),
                grouped: b.isGroup,
                airing: ProgramGroupingFixtures.airingDates.map { .init(date: $0, value: b.isAiring(at: Date(timeIntervalSince1970: $0))) }
            )
        }
        #expect(actual == scenario.expected, "Original mismatch: \(scenario.name)")
    }
}
