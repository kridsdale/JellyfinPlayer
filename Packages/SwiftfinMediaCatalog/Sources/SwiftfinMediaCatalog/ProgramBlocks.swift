//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation
import JellyfinAPI

struct ClampedProgram {

    let program: BaseItemDto
    let start: Date
    let end: Date

    var isShort: Bool {
        end.timeIntervalSince(start) < 15 * 60
    }

    init?(_ program: BaseItemDto, clampedTo span: ClosedRange<Date>) {
        guard let start = program.startDate, let end = program.endDate else { return nil }

        let clampedStart = max(start, span.lowerBound)
        let clampedEnd = min(end, span.upperBound)

        guard clampedEnd > clampedStart else { return nil }

        self.program = program
        self.start = clampedStart
        self.end = clampedEnd
    }
}

//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation
import JellyfinAPI
import SwiftfinCollections

public struct ProgramBlock: Identifiable, Sendable {

    public struct ID: Hashable, Sendable {

        public let channelID: String?
        public let programIDs: [String?]
        public let start: Date
        public let end: Date
    }

    public let id: ID
    public let programs: [BaseItemDto]
    public let start: Date
    public let end: Date

    public var isGroup: Bool {
        programs.count > 1
    }

    init(
        programs: [BaseItemDto],
        start: Date,
        end: Date
    ) {
        self.id = ID(
            channelID: programs.first?.channelID,
            programIDs: programs.map(\.id),
            start: start,
            end: end
        )
        self.programs = programs
        self.start = start
        self.end = end
    }

    public func isAiring(at date: Date) -> Bool {
        programs.contains { program in
            guard let start = program.startDate, let end = program.endDate else { return false }
            return start <= date && date < end
        }
    }
}

public extension Collection<BaseItemDto> {

    func programBlocks(
        startDate: Date,
        endDate: Date
    ) -> [ProgramBlock] {
        guard startDate <= endDate else { return [] }
        let clampedPrograms = compactMap { ClampedProgram($0, clampedTo: startDate ... endDate) }
            .sorted { $0.start < $1.start }

        var chunks: [[ClampedProgram]] = []
        var currentChunk: [ClampedProgram] = []
        var currentEnd: Date?

        for program in clampedPrograms {
            let joinsCurrentChunk = program.isShort &&
                currentChunk.first?.isShort == true &&
                currentEnd.map { program.start <= $0 } == true

            if currentChunk.isNotEmpty, !joinsCurrentChunk {
                chunks.append(currentChunk)
                currentChunk.removeAll(keepingCapacity: true)
                currentEnd = nil
            }

            currentChunk.append(program)
            if let previousEnd = currentEnd {
                currentEnd = previousEnd > program.end ? previousEnd : program.end
            } else {
                currentEnd = program.end
            }
        }

        if currentChunk.isNotEmpty {
            chunks.append(currentChunk)
        }

        return chunks.compactMap { chunk in
            guard let first = chunk.first,
                  let end = chunk.map(\.end).max()
            else { return nil }

            return ProgramBlock(
                programs: chunk.map(\.program),
                start: first.start,
                end: end
            )
        }
    }
}
