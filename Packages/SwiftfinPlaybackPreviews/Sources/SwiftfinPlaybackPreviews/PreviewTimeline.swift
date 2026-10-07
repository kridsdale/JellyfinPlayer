//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation

public struct PreviewChapter: Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    public let start: Duration?
    public let url: URL?
    public init(start: Duration?, url: URL?) {
        self.start = start
        self.url = url
    }

    public var description: String {
        "PreviewChapter(<redacted>)"
    }

    public var debugDescription: String {
        description
    }
}

public enum ChapterPreviewTimeline {
    public static func index(for seconds: Duration, chapters: [PreviewChapter]) -> Int? {
        let seconds = max(.zero, seconds)
        return chapters.lastIndex { $0.start.map { $0 <= seconds } == true }
            ?? chapters.firstIndex { $0.start != nil }
    }
}

public struct PreviewTileAddress: Sendable, Equatable {
    public let sheet: Int
    public let tile: Int
    public let interval: Int
    public init(sheet: Int, tile: Int, interval: Int) {
        self.sheet = sheet
        self.tile = tile
        self.interval = interval
    }
}

public struct TrickplayPreviewLayout: Sendable {
    public let columns: Int
    public let rows: Int
    public let width: Int
    public let interval: Duration
    public let runtime: Duration
    private let area: Int
    public init?(columns: Int, rows: Int, width: Int, intervalMilliseconds: Int, runtime: Duration) {
        let product = columns.multipliedReportingOverflow(by: rows)
        guard columns > 0, rows > 0, width > 0, intervalMilliseconds > 0,
              !product.overflow, product.partialValue > 0, runtime > .zero else { return nil }
        self.columns = columns
        self.rows = rows
        self.width = width
        interval = .milliseconds(intervalMilliseconds)
        self.runtime = runtime
        area = product.partialValue
    }

    public func address(for seconds: Duration) -> PreviewTileAddress? {
        let time = min(max(.zero, seconds), max(.zero, runtime - .nanoseconds(1)))
        let index = (time / interval).rounded(.down)
        guard index.isFinite, index >= 0, index < Double(Int.max) else { return nil }
        let value = Int(index)
        return .init(sheet: value / area, tile: value % area, interval: value)
    }

    public func adjacentSheets(to address: PreviewTileAddress) -> [Int] {
        var result: [Int] = []
        if address.sheet > 0 {
            result.append(address.sheet - 1)
        }
        if let last = self.address(for: runtime), address.sheet < last.sheet {
            result.append(address.sheet + 1)
        }
        return result
    }
}
