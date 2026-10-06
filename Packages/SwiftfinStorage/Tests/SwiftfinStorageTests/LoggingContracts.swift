//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import CoreStore
import os
@testable import SwiftfinStorage
import Testing

struct LoggingContracts {
    @Test
    func `legacy native levels retain their host severity and source context`() {
        let values = OSAllocatedUnfairLock(initialState: [StorageLogEntry]())
        let logger = NativeStorageLogger { value in values.withLock { $0.append(value) } }
        for level in [CoreStore.LogLevel.trace, .notice, .warning, .fatal] {
            logger.log(level: level, message: "synthetic", fileName: "file", lineNumber: 12, functionName: "function")
        }
        let captured = values.withLock { $0 }
        #expect(captured.map(\.level) == [.trace, .debug, .warning, .critical])
        #expect(captured.allSatisfy { $0.message == "synthetic" && $0.file == "file" && $0.line == 12 && $0.function == "function" })
    }

    @Test
    func `successful assertions do not evaluate diagnostics and failures preserve severity`() {
        let values = OSAllocatedUnfairLock(initialState: [StorageLogEntry]())
        let logger = NativeStorageLogger { value in values.withLock { $0.append(value) } }
        var evaluated = 0
        func message() -> String {
            evaluated += 1
            return "synthetic failure"
        }
        logger.assert(true, message: message(), fileName: "file", lineNumber: 1, functionName: "function")
        #expect(evaluated == 0 && values.withLock { $0.isEmpty })
        logger.assert(values.withLock { !$0.isEmpty }, message: message(), fileName: "file", lineNumber: 2, functionName: "function")
        #expect(evaluated == 1 && values.withLock { $0.first?.level == .critical })
    }

    @Test
    func `native worker diagnostics carry checked immutable values across executors`() async {
        let count = OSAllocatedUnfairLock(initialState: 0)
        let logger = NativeStorageLogger { _ in count.withLock { $0 += 1 } }
        await withTaskGroup(of: Void.self) { group in
            for _ in 0 ..< 64 {
                group.addTask {
                    logger.log(level: .notice, message: "synthetic", fileName: "file", lineNumber: 1, functionName: "function")
                }
            }
        }
        #expect(count.withLock { $0 } == 64)
    }
}

@MainActor
struct LoggingStartupContracts {
    @Test
    func `bootstrap writes once and cannot be replaced after database startup`() {
        var writes = 0
        let gate = StorageLoggingStartupGate { _ in writes += 1 }
        let logger = NativeStorageLogger { _ in }
        #expect(gate.bootstrap(logger))
        #expect(!gate.bootstrap(logger))
        gate.freeze()
        #expect(!gate.bootstrap(logger) && writes == 1)
    }

    @Test
    func `database construction before bootstrap prevents any native global write`() {
        var writes = 0
        let gate = StorageLoggingStartupGate { _ in writes += 1 }
        gate.freeze()
        #expect(!gate.bootstrap(NativeStorageLogger { _ in }) && writes == 0)
    }
}
