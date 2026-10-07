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

struct ChapterSelectionContracts {
    @Test
    func `empty and untimed lists preserve overlay selection`() {
        #expect(ChapterSelectionTimeline(starts: []).index(at: .zero) == nil)
        #expect(ChapterSelectionTimeline(starts: [nil, nil, nil]).index(at: .zero) == 2)
        #expect(ChapterSelectionTimeline(starts: [nil]).index(at: .seconds(-1)) == 0)
    }

    @Test
    func `unknown predecessor remains selectable`() {
        let timeline = ChapterSelectionTimeline(starts: [.zero, nil, .seconds(10), nil])
        #expect(timeline.index(at: .seconds(9)) == 1)
        #expect(timeline.index(at: .seconds(10)) == 3)
        #expect(timeline.index(at: .seconds(100)) == 3)
    }

    @Test
    func `source order and duplicate timestamps remain unchanged`() {
        let unsorted = ChapterSelectionTimeline(starts: [.zero, .seconds(10), .seconds(5)])
        #expect(unsorted.index(at: .seconds(7)) == 0)
        #expect(unsorted.index(at: .seconds(10)) == 2)
        let duplicates = ChapterSelectionTimeline(starts: [.zero, .zero, .seconds(10)])
        #expect(duplicates.index(at: .zero) == 1)
        #expect(duplicates.index(at: .seconds(-1)) == 0)
    }

    @Test
    func `fractional boundaries retain strictly later comparison`() {
        let tick = Duration(secondsComponent: 0, attosecondsComponent: 1)
        let timeline = ChapterSelectionTimeline(starts: [.zero, tick, .seconds(1)])
        #expect(timeline.index(at: .zero - tick) == 0)
        #expect(timeline.index(at: .zero) == 0)
        #expect(timeline.index(at: tick) == 1)
        #expect(timeline.index(at: .seconds(1)) == 2)
        let extremes = ChapterSelectionTimeline(starts: [.seconds(Int64.min), .seconds(Int64.max)])
        #expect(extremes.index(at: .seconds(Int64.min)) == 0)
        #expect(extremes.index(at: .seconds(Int64.max)) == 1)
    }

    @Test
    func `overlay selection keeps its distinct thumbnail semantics`() {
        let starts: [Duration?] = [.zero, .seconds(10), .seconds(5)]
        let timeline = ChapterSelectionTimeline(starts: starts)
        let previews = starts.map { PreviewChapter(start: $0, url: nil) }
        #expect(timeline.index(at: .seconds(7)) == 0)
        #expect(ChapterPreviewTimeline.index(for: .seconds(7), chapters: previews) == 2)
        #expect(ChapterSelectionTimeline(starts: [nil, nil]).index(at: .zero) == 1)
        #expect(ChapterPreviewTimeline.index(for: .zero, chapters: [.init(start: nil, url: nil)]) == nil)
    }

    @Test
    func `prepared timeline retains an immutable input snapshot`() {
        var starts: [Duration?] = [.zero, .seconds(10)]
        let timeline = ChapterSelectionTimeline(starts: starts)
        starts.removeAll()
        #expect(timeline.index(at: .seconds(10)) == 1)
        #expect(starts.isEmpty)
    }
}
