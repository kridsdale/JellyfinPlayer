//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation
import JellyfinAPI
@testable import SwiftfinMediaCatalog
import Testing

struct ProgramGroupingContracts {
    private func blocks(_ scenario: ProgramGroupingScenario) -> [ProgramBlock] {
        scenario.samples.map(\.item).programBlocks(
            startDate: Date(timeIntervalSince1970: scenario.start),
            endDate: Date(timeIntervalSince1970: scenario.end)
        )
    }

    @Test
    func `missing reversed zero and outside programs are omitted`() {
        #expect(blocks(ProgramGroupingFixtures.scenarios[1]).isEmpty)
    }

    @Test
    func `touching short programs merge using the furthest existing end`() {
        let result = blocks(ProgramGroupingFixtures.scenarios[2])
        #expect(result.count == 1)
        #expect(result.first?.programs.map(\.id) == ["a", "b", "c", "d"])
        #expect(result.first?.start == Date(timeIntervalSince1970: 0))
        #expect(result.first?.end == Date(timeIntervalSince1970: 700))
        #expect(result.first?.isGroup == true)
    }

    @Test
    func `gaps and the exact fifteen minute threshold remain separate`() {
        #expect(blocks(ProgramGroupingFixtures.scenarios[3]).count == 2)
        #expect(blocks(ProgramGroupingFixtures.scenarios[4]).map { $0.programs.map(\.id) } == [["a"], ["long"], ["b"]])
    }

    @Test
    func `clipped duration controls grouping without changing program payloads`() {
        let scenario = ProgramGroupingFixtures.scenarios[5]
        let result = blocks(scenario)
        #expect(result.count == 2 && result[0].programs.count == 2)
        #expect(result[0].programs.map(ProgramGroupingSample.init) == Array(scenario.samples.prefix(2)))
        #expect(result[0].start == Date(timeIntervalSince1970: 0) && result[0].end == Date(timeIntervalSince1970: 200))
        #expect(result[1].end == Date(timeIntervalSince1970: 3600))
    }

    @Test
    func `identity retains nil duplicate and original channel values`() {
        let result = blocks(ProgramGroupingFixtures.scenarios[7])
        #expect(result.count == 1)
        #expect(result[0].id.channelID == nil && result[0].id.programIDs == [nil, "duplicate", "duplicate"])
        #expect(result[0].programs.map(ProgramGroupingSample.init) == ProgramGroupingFixtures.scenarios[7].samples)
    }

    @Test
    func `airing uses original half open dates and invalid windows do not trap`() {
        let item = ProgramGroupingSample("a", 0, 10).item
        let result = [item].programBlocks(startDate: Date(timeIntervalSince1970: 5), endDate: Date(timeIntervalSince1970: 9))
        #expect(result[0].isAiring(at: Date(timeIntervalSince1970: 0)))
        #expect(!result[0].isAiring(at: Date(timeIntervalSince1970: 10)))
        #expect([item].programBlocks(startDate: Date(timeIntervalSince1970: 5), endDate: Date(timeIntervalSince1970: 5)).isEmpty)
        #expect([item].programBlocks(startDate: Date(timeIntervalSince1970: 10), endDate: Date(timeIntervalSince1970: 0)).isEmpty)
    }
}
