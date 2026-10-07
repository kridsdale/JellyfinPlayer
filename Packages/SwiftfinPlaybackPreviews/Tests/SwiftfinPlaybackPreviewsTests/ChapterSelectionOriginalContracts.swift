//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation
import SwiftfinPlaybackPreviews
import Testing

private struct OriginalChapterTime: Decodable {
    let seconds: Int64
    let attoseconds: Int64
    var duration: Duration {
        .init(secondsComponent: seconds, attosecondsComponent: attoseconds)
    }
}

private struct OriginalChapterFixture: Decodable {
    let originalCommit: String
    let sourceHashes: [String: String]
    let memberHashes: [String: String]
    let vectors: [[OriginalChapterTime?]]
    let queries: [OriginalChapterTime]
    let expected: [[Int?]]
}

struct ChapterSelectionOriginalContracts {
    private func fixture() throws -> OriginalChapterFixture {
        let url = try #require(Bundle.module.url(forResource: "chapter-selection-original-453c223f", withExtension: "json"))
        return try JSONDecoder().decode(OriginalChapterFixture.self, from: Data(contentsOf: url))
    }

    @Test
    func `original chapter source and method provenance`() throws {
        let original = try fixture()
        #expect(original.originalCommit == "453c223fa9eb1f3fa97747440c908c3a69bfcc96")
        #expect(original.sourceHashes == [
            "Packages/SwiftfinCollections/Sources/SwiftfinCollections/Collection.swift": "e51e1973694f653f468ca3963dbdaab0ec5b72a007a3efda63e9cac9b4839a7a",
            "Shared/Objects/MediaPlayerManager/Supplements/MediaChaptersSupplement.swift": "4218810e5f66711be8116af0b6f933cbab629a6bd9e53ea00f94598bc5787a74"
        ])
        #expect(original.memberHashes == [
            "chapterID": "a7934a273868810d59c96886bc5aa24a52baee0d35522c294b8cc9cac0220a3c",
            "safeSubscript": "bdb1a1cc2f7ee3a885c6f503a9f3e7cbe94fea9789f294b1b0b78b379a5a31e0"
        ])
        #expect(original.vectors.count == 783 && original.queries.count == 11)
        #expect(original.expected.reduce(0) { $0 + $1.count } == 8613)
    }

    @Test
    func `all independently captured original chapter selections match`() throws {
        let original = try fixture()
        #expect(original.expected.count == original.vectors.count)
        for (starts, expected) in zip(original.vectors, original.expected) {
            let timeline = ChapterSelectionTimeline(starts: starts.map { $0?.duration })
            #expect(original.queries.map { timeline.index(at: $0.duration) } == expected)
        }
    }
}
