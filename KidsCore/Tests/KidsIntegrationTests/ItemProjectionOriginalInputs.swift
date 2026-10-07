//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation
import JellyfinAPI

struct ProjectionPersonInput: Codable, Equatable, Sendable {
    let id: String?
    let kind: String?
    let role: String?
    let name: String
    init(_ id: String?, _ kind: PersonKind?, _ role: String?, name: String = "Synthetic") {
        self.id = id
        self.kind = kind?.rawValue
        self.role = role
        self.name = name
    }

    init(_ person: BaseItemPerson) {
        id = person.id
        kind = person.type?.rawValue
        role = person.role
        name = person.name ?? ""
    }

    var item: BaseItemPerson {
        var p = BaseItemPerson()
        p.id = id
        p.type = kind.flatMap(PersonKind.init(rawValue:))
        p.role = role
        p.name = name
        return p
    }
}

struct ProjectionTimeInput: Codable, Sendable {
    let name: String
    let start: Double?
    let end: Double?
    let premiere: Double?
    let ticks: Int?
    let position: Int?
    let percentage: Double?
    let nested: Bool
    var item: BaseItemDto {
        var item = BaseItemDto()
        item.startDate = start.map { Date(timeIntervalSince1970: $0) }
        item.endDate = end.map { Date(timeIntervalSince1970: $0) }
        item.premiereDate = premiere.map { Date(timeIntervalSince1970: $0) }
        item.runTimeTicks = ticks
        var data = UserItemDataDto(key: "synthetic")
        data.playbackPositionTicks = position
        data.playedPercentage = percentage
        item.userData = data
        if nested {
            var child = BaseItemDto()
            child.startDate = Date(timeIntervalSince1970: 90)
            child.endDate = Date(timeIntervalSince1970: 110)
            child.timerID = "child-timer"
            item.currentProgram = child
        }
        return item
    }
}

struct ProjectionFixture: Codable {
    let originalCommit: String
    let sourceHashes: [String: String]
    let memberHashes: [String: String]
    let clockInjection: String
    let kindValues: [String?]
    let kindMasks: [Int]
    let permissionMasks: [Int]
    let timeInputs: [ProjectionTimeInput]
    let timeNumbers: [[String?]]
    let timeMasks: [Int]
    let roleInputs: [ProjectionPersonInput]
    let roleOutputs: [String?]
    let crewInputs: [[ProjectionPersonInput]?]
    let crewOutputs: [[ProjectionPersonInput]?]
    let personFacts: [[String?]]
    let streamIndices: [[Int?]]
}

struct ProjectionProvenance: Codable {
    let originalCommit: String
    let sourceHashes: [String: String]
    let memberHashes: [String: String]
    let clockInjection: String
}

enum ProjectionInputs {
    static let flags: [Bool?] = [nil, false, true]
    static var kinds: [BaseItemKind?] {
        [nil] + BaseItemKind.allCases.map(Optional.some)
    }

    static let now = Date(timeIntervalSince1970: 100)
    static let timeInputs: [ProjectionTimeInput] = [
        .init(name: "missing", start: nil, end: nil, premiere: nil, ticks: nil, position: nil, percentage: nil, nested: false),
        .init(name: "live-mid", start: 40, end: 120, premiere: 80, ticks: 12_000_000_000, position: 750_009, percentage: 25, nested: false),
        .init(name: "inclusive-end", start: 40, end: 100, premiere: 80, ticks: 0, position: 0, percentage: 0, nested: false),
        .init(name: "future", start: 120, end: 180, premiere: 0, ticks: -10, position: -11, percentage: -10, nested: false),
        .init(name: "ended", start: 0, end: 90, premiere: 150, ticks: 9_999_999, position: 9_999_999, percentage: 120, nested: false),
        .init(name: "zero-length", start: 100, end: 100, premiere: 0, ticks: 10, position: 10, percentage: 10, nested: false),
        .init(name: "inverted", start: 120, end: 40, premiere: 0, ticks: 100, position: 100, percentage: 50, nested: false),
        .init(name: "missing-end", start: 90, end: nil, premiere: 150, ticks: Int.max, position: Int.min, percentage: 50, nested: false),
        .init(name: "premiere-only", start: nil, end: nil, premiere: 150, ticks: 1, position: 1, percentage: 0, nested: false),
        .init(name: "nested", start: 120, end: 40, premiere: 0, ticks: 100, position: 100, percentage: 50, nested: true)
    ]
    static let roles: [String?] = [
        nil,
        "",
        "Solo",
        "First / Second",
        " First  / Second (voice) ",
        "First (a) / Last (b)",
        "/First/",
        "First / Last",
        "\tFirst / Last (角色)",
        "First / Last (nested (x))"
    ]
    static var roleInputs: [ProjectionPersonInput] {
        ([nil] + PersonKind.allCases.map(Optional.some)).flatMap { kind in roles.map { .init(
            "id",
            kind,
            $0
        ) } }
    }

    static let crewInputs: [[ProjectionPersonInput]?] = [
        nil, [], [.init("a", .actor, "A"), .init("a", .actor, "B")],
        [.init("a", .director, "Director"), .init("a", .writer, "Writer"), .init("a", .producer, "Writer")],
        [.init("a", .actor, "Actor"), .init("a", .director, "Director"), .init("a", .writer, "Writer")],
        [.init(nil, .director, "D"), .init(nil, .writer, "W")],
        [.init("", .director, nil), .init("", .writer, "")],
        [.init("a", .director, " "), .init("b", .writer, "B"), .init("a", .writer, "Director"), .init("a", .producer, " ")]
    ]
    static func policy(admin: Bool?, flag: Bool?, group: Int) -> UserPolicy {
        var p = UserPolicy(
            authenticationProviderID: "synthetic",
            enableCollectionManagement: false,
            enableLyricManagement: false,
            enableSubtitleManagement: false,
            passwordResetProviderID: "synthetic"
        )
        p.isAdministrator = admin
        p.enableMediaPlayback = flag
        if group == 0 || group == 5 {
            p.enableContentDownloading = flag
        }
        if group == 1 || group == 5 {
            p.enableCollectionManagement = flag == true
        }
        if group == 2 || group == 5 {
            p.enableLyricManagement = flag == true
        }
        if group == 3 || group == 5 {
            p.enableSubtitleManagement = flag == true
        }
        return p
    }

    static func basic(_ kind: BaseItemKind?) -> BaseItemDto {
        var item = BaseItemDto()
        item.type = kind
        item.album = "album"
        item.albumArtist = "artist"
        item.seriesName = "series"
        item.channelName = "channel"
        item.seriesID = "series-id"
        item.parentID = "parent-id"
        item.premiereDate = Date(timeIntervalSince1970: 88)
        item.endDate = Date(timeIntervalSince1970: 120)
        item.productionLocations = ["", " ", "place"]
        item.criticRating = 0
        item.externalURLs = []
        return item
    }

    static func streams() -> [MediaStream] {
        ([nil] + MediaStreamType.allCases.map(Optional.some)).enumerated().map { index, type in
            var stream = MediaStream()
            stream.index = index
            stream.type = type
            return stream
        }
    }

    static func mask(_ values: [Bool]) -> Int {
        values.enumerated().reduce(0) { $0 | ($1.element ? (1 << $1.offset) : 0) }
    }
}
