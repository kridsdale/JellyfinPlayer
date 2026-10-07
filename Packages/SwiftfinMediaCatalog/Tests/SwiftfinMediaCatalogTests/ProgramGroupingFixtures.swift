//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation
import JellyfinAPI

struct ProgramGroupingSample: Codable, Equatable, Sendable {
    let id: String?
    let channel: String?
    let name: String
    let start: Double?
    let end: Double?
    var item: BaseItemDto {
        var item = BaseItemDto(id: id)
        item.channelID = channel
        item.name = name
        item.startDate = start.map { Date(timeIntervalSince1970: $0) }
        item.endDate = end.map { Date(timeIntervalSince1970: $0) }
        return item
    }

    init(_ id: String?, _ start: Double?, _ end: Double?, channel: String? = "channel") {
        self.id = id
        self.channel = channel
        self.name = "Synthetic " + (id ?? "nil")
        self.start = start
        self.end = end
    }

    init(_ item: BaseItemDto) {
        id = item.id
        channel = item.channelID
        name = item.name ?? ""
        start = item.startDate?.timeIntervalSince1970
        end = item.endDate?.timeIntervalSince1970
    }
}

struct ProgramGroupingScenario: Sendable {
    let name: String
    let start: Double
    let end: Double
    let samples: [ProgramGroupingSample]
    init(_ name: String, _ samples: [ProgramGroupingSample], start: Double = 0, end: Double = 3600) {
        self.name = name
        self.samples = samples
        self.start = start
        self.end = end
    }
}

enum ProgramGroupingFixtures {
    static let scenarios: [ProgramGroupingScenario] = [
        .init("empty", []),
        .init(
            "missing-invalid-outside",
            [
                .init("missing-start", nil, 100),
                .init("missing-end", 100, nil),
                .init("reversed", 100, 10),
                .init("zero", 20, 20),
                .init("before", -500, -1),
                .init("after", 3600, 3700)
            ]
        ),
        .init("overlap-touch-chain", [.init("c", 300, 600), .init("a", 0, 400), .init("b", 100, 200), .init("d", 600, 700)]),
        .init("gap", [.init("a", 0, 300), .init("b", 301, 400)]),
        .init("exact-long-threshold", [.init("a", 0, 100), .init("long", 100, 1000), .init("b", 1000, 1100)]),
        .init("clipped-original-long", [.init("long", -1000, 100), .init("short", 100, 200), .init("right", 3500, 10000)]),
        .init(
            "long-short-overlap",
            [.init("short", 100, 300), .init("long", 0, 1000), .init("short2", 200, 400), .init("long2", 250, 2000)]
        ),
        .init(
            "equal-start-identities",
            [.init(nil, 10, 20, channel: nil), .init("duplicate", 10, 30, channel: "other"), .init("duplicate", 10, 25)]
        ),
        .init("fractional-window", [.init("a", -10, 100.25), .init("b", 100.25, 200.5), .init("c", 200.75, 300.5)], start: 0.5, end: 300.25)
    ]
    static let airingDates: [Double] = [-100, -1, 0, 10, 99.5, 100, 100.25, 300, 700, 899, 900, 1000, 3599, 3600, 9999]
}
