//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation
import JellyfinAPI
import SwiftfinServerOperations
import Testing

struct AppServerOriginalContracts {
    private struct Fixture: Decodable {
        struct Trigger: Decodable { let type: String
            let encoded: String
        }

        struct Log: Decodable { let name: String
            let kind: String
        }

        let triggers: [Trigger]
        let logs: [Log]
    }

    private let original = #"""
    {
      "logs": [
        {
          "kind": "directStream",
          "name": "FFmpeg.DirectStream-X.log"
        },
        {
          "kind": "directStream",
          "name": "FFmpeg.DirectStream-"
        },
        {
          "kind": "remux",
          "name": "FFmpeg.Remux-1.log"
        },
        {
          "kind": "transcode",
          "name": "FFmpeg.Transcode-1.log"
        },
        {
          "kind": "system",
          "name": "log_20260101.log"
        },
        {
          "kind": "system",
          "name": "log_99999999.log"
        },
        {
          "kind": "system",
          "name": "log_١٢٣٤٥٦٧٨.log"
        },
        {
          "kind": "system",
          "name": "log_２０２６０１０１.log"
        },
        {
          "kind": "system",
          "name": "log_00000000.log"
        },
        {
          "kind": "other",
          "name": "log_202610071.log"
        },
        {
          "kind": "other",
          "name": "xlog_20261007.log"
        },
        {
          "kind": "other",
          "name": "log_20261007.log\n"
        },
        {
          "kind": "other",
          "name": "Log_20261007.log"
        },
        {
          "kind": "other",
          "name": "log_20261007.LOG"
        },
        {
          "kind": "other",
          "name": "FFmpeg.directStream-X.log"
        },
        {
          "kind": "other",
          "name": " FFmpeg.Remux-X"
        },
        {
          "kind": "other",
          "name": ""
        },
        {
          "kind": "other",
          "name": "system"
        },
        {
          "kind": "other",
          "name": "directStream"
        },
        {
          "kind": "other",
          "name": "remux"
        },
        {
          "kind": "other",
          "name": "transcode"
        },
        {
          "kind": "other",
          "name": "other"
        },
        {
          "kind": "transcode",
          "name": "FFmpeg.Transcode-log_20260101.log"
        }
      ],
      "triggers": [
        {
          "encoded": "{\"TimeOfDayTicks\":0,\"Type\":\"DailyTrigger\"}",
          "type": "DailyTrigger"
        },
        {
          "encoded": "{\"DayOfWeek\":\"Sunday\",\"TimeOfDayTicks\":0,\"Type\":\"WeeklyTrigger\"}",
          "type": "WeeklyTrigger"
        },
        {
          "encoded": "{\"IntervalTicks\":36000000000,\"Type\":\"IntervalTrigger\"}",
          "type": "IntervalTrigger"
        },
        {
          "encoded": "{\"Type\":\"StartupTrigger\"}",
          "type": "StartupTrigger"
        }
      ]
    }
    """#
    private func fixture() throws -> Fixture {
        try JSONDecoder().decode(Fixture.self, from: Data(original.utf8))
    }

    @Test
    func `all original trigger defaults retain exact encoded fields`() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        for row in try fixture().triggers {
            let type = try #require(TaskTriggerInfoType(rawValue: row.type))
            let actual = ServerOperationsPolicy.defaultTrigger(type: type)
            #expect(try String(decoding: encoder.encode(actual), as: UTF8.self) == row.encoded)
        }
    }

    @Test
    func `all captured log names preserve classification anchors case and Unicode digits`() throws {
        for row in try fixture().logs {
            #expect(ServerLogKind(rawValue: row.name).rawValue == row.kind)
        }
        #expect(ServerLogKind.allCases.map(\.rawValue) == ["directStream", "remux", "transcode", "system", "other"])
    }

    @Test
    func `log kind transfers as an immutable value and raw initializer stays filename based`() async {
        let kind = await Task.detached { ServerLogKind(rawValue: "FFmpeg.Remux-test") }.value
        #expect(kind == .remux && ServerLogKind(rawValue: kind.rawValue) == .other)
    }
}
