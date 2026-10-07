//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation
import SwiftfinAccountModels
import Testing

struct ServerSelectionContracts {
    @Test
    func `original raw JSON and reserved sentinel round trips remain exact`() throws {
        let fixture = try ServerSelectionOriginalFixture.load()
        #expect(fixture.cases.count == 8)
        #expect(fixture.equalities.count == 8 && fixture.equalities.allSatisfy { $0.count == 8 })
        #expect(Set(fixture.cases.map(\.value)).count == fixture.hashSetCount)
        for (index, lhs) in fixture.cases.enumerated() {
            for (otherIndex, rhs) in fixture.cases.enumerated() {
                #expect((lhs.value == rhs.value) == fixture.equalities[index][otherIndex])
            }
        }
        #expect(fixture.original.commit == "98e6c8b7436ac9cb340bd06dc4a2700b7150cbe2")
        for sample in fixture.cases {
            #expect(sample.value.rawValue == sample.raw)
            #expect(try String(decoding: JSONEncoder().encode(sample.value), as: UTF8.self) == sample.json)
            let decoded = try JSONDecoder().decode(ServerSelection.self, from: Data(sample.json.utf8))
            switch decoded {
            case .all: #expect(sample.roundtripKind == "all")
            case .server: #expect(sample.roundtripKind == "server")
            }
            #expect(ServerSelection(rawValue: sample.raw) == decoded)
        }
    }

    @Test
    func `first exact ID preserves duplicate order empty whitespace and Unicode`() throws {
        let records = ServerSelectionOriginalFixture.records
        for sample in try ServerSelectionOriginalFixture.load().cases {
            let expected = sample.selectedIndex < 0 ? nil : records[sample.selectedIndex]
            #expect(sample.value.server(from: records) == expected)
        }
        #expect(ServerSelection.server(id: "A").server(from: records.reversed())?.name == "record-1")
        #expect(ServerSelection.all.server(from: records) == nil)
        #expect(ServerSelection.server(id: "absent").server(from: records) == nil)
    }

    @Test
    func `single pass lookup stops at first exact record and all consumes nothing`() {
        let records = ServerSelectionOriginalFixture.records
        var visited = 0
        let sequence = AnySequence<ServerAccountRecord> {
            var iterator = records.makeIterator()
            return AnyIterator {
                visited += 1
                return iterator.next()
            }
        }
        #expect(ServerSelection.all.server(from: sequence) == nil)
        #expect(visited == 0)
        #expect(ServerSelection.server(id: "A").server(from: sequence)?.name == "record-0")
        #expect(visited == 1)
    }

    @Test
    func `checked values cross a worker executor without settings or account services`() async {
        let record = ServerSelectionOriginalFixture.records[0]
        let selection = ServerSelection.server(id: record.id)
        let result = await Task.detached { selection.server(from: [record]) }.value
        #expect(result == record)
    }
}
