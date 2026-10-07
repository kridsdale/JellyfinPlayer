//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation
import SwiftfinTime
import Testing

struct AppTickOriginalContracts {
    private struct Row: Decodable {
        struct Components: Decodable { let seconds: Int64
            let attoseconds: Int64
        }

        let input: Int?
        let seconds: Int?
        let components: Components?
    }

    private let original = #"""
    [
      {
        "components": null,
        "input": null,
        "seconds": null
      },
      {
        "components": {
          "attoseconds": -477580000000000000,
          "seconds": -922337203685
        },
        "input": -9223372036854775808,
        "seconds": -922337203685
      },
      {
        "components": {
          "attoseconds": 0,
          "seconds": -1
        },
        "input": -10000001,
        "seconds": -1
      },
      {
        "components": {
          "attoseconds": 0,
          "seconds": -1
        },
        "input": -10000000,
        "seconds": -1
      },
      {
        "components": {
          "attoseconds": -999999000000000000,
          "seconds": 0
        },
        "input": -9999999,
        "seconds": 0
      },
      {
        "components": {
          "attoseconds": -1000000000000,
          "seconds": 0
        },
        "input": -11,
        "seconds": 0
      },
      {
        "components": {
          "attoseconds": -1000000000000,
          "seconds": 0
        },
        "input": -10,
        "seconds": 0
      },
      {
        "components": {
          "attoseconds": 0,
          "seconds": 0
        },
        "input": -9,
        "seconds": 0
      },
      {
        "components": {
          "attoseconds": 0,
          "seconds": 0
        },
        "input": -1,
        "seconds": 0
      },
      {
        "components": {
          "attoseconds": 0,
          "seconds": 0
        },
        "input": 0,
        "seconds": 0
      },
      {
        "components": {
          "attoseconds": 0,
          "seconds": 0
        },
        "input": 1,
        "seconds": 0
      },
      {
        "components": {
          "attoseconds": 0,
          "seconds": 0
        },
        "input": 9,
        "seconds": 0
      },
      {
        "components": {
          "attoseconds": 1000000000000,
          "seconds": 0
        },
        "input": 10,
        "seconds": 0
      },
      {
        "components": {
          "attoseconds": 1000000000000,
          "seconds": 0
        },
        "input": 11,
        "seconds": 0
      },
      {
        "components": {
          "attoseconds": 999999000000000000,
          "seconds": 0
        },
        "input": 9999999,
        "seconds": 0
      },
      {
        "components": {
          "attoseconds": 0,
          "seconds": 1
        },
        "input": 10000000,
        "seconds": 1
      },
      {
        "components": {
          "attoseconds": 0,
          "seconds": 1
        },
        "input": 10000001,
        "seconds": 1
      },
      {
        "components": {
          "attoseconds": 477580000000000000,
          "seconds": 922337203685
        },
        "input": 9223372036854775807,
        "seconds": 922337203685
      }
    ]
    """#
    @Test
    func `all original signed and extreme ticks preserve truncation and nil projections`() throws {
        for row in try JSONDecoder().decode([Row].self, from: Data(original.utf8)) {
            let duration = row.input.map(Duration.ticks)
            let seconds = row.input.map { Duration.wholeSeconds(ticks: $0) }
            #expect(seconds == row.seconds)
            #expect(duration?.components.seconds == row.components?.seconds)
            #expect(duration?.components.attoseconds == row.components?.attoseconds)
        }
    }

    @Test
    func `immutable tick outputs can be read on another executor`() async {
        let output = await Task.detached { (Duration.ticks(-11), Duration.wholeSeconds(ticks: -10_000_001)) }.value
        #expect(output.0 == .microseconds(-1) && output.1 == -1)
    }
}
