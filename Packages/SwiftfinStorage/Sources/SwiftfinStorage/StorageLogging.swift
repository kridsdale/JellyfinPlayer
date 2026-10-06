//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import CoreStore
import Foundation

public enum StorageLogLevel: Equatable, Sendable { case trace, debug, warning, critical }
public struct StorageLogEntry: Sendable {
    public let level: StorageLogLevel
    public let message: String
    public let file: String
    public let line: UInt
    public let function: String
}

/// Install at process startup, before creating any owned database. The native
/// global is written once and never reconfigured while SDK workers can read it.
@MainActor
public enum StorageLogging {
    private static let gate = StorageLoggingStartupGate(install: installLegacyCoreStoreLogger)

    @discardableResult
    public static func bootstrap(_ emit: @escaping @Sendable (StorageLogEntry) -> Void) -> Bool {
        gate.bootstrap(NativeStorageLogger(emit: emit))
    }

    static func freeze() {
        gate.freeze()
    }
}

@MainActor
final class StorageLoggingStartupGate {
    private enum Phase { case fresh, installed, frozen }
    private var phase: Phase = .fresh
    private let install: @MainActor (NativeStorageLogger) -> Void
    init(install: @escaping @MainActor (NativeStorageLogger) -> Void) {
        self.install = install
    }

    func bootstrap(_ logger: NativeStorageLogger) -> Bool {
        guard phase == .fresh else { return false }
        phase = .installed
        install(logger)
        return true
    }

    func freeze() {
        phase = .frozen
    }
}

struct NativeStorageLogger: CoreStoreLogger, Sendable {
    let emit: @Sendable (StorageLogEntry) -> Void

    func log(error: CoreStoreError, message: String, fileName: StaticString, lineNumber: Int, functionName: StaticString) {
        send(.critical, message, fileName, lineNumber, functionName)
    }

    func log(level: LogLevel, message: String, fileName: StaticString, lineNumber: Int, functionName: StaticString) {
        let value: StorageLogLevel = switch level {
        case .trace: .trace
        case .notice: .debug
        case .warning: .warning
        case .fatal: .critical
        }
        send(value, message, fileName, lineNumber, functionName)
    }

    func assert(
        _ condition: @autoclosure () -> Bool,
        message: @autoclosure () -> String,
        fileName: StaticString,
        lineNumber: Int,
        functionName: StaticString
    ) {
        guard !condition() else { return }
        send(.critical, message(), fileName, lineNumber, functionName)
    }

    private func send(_ level: StorageLogLevel, _ message: String, _ file: StaticString, _ line: Int, _ function: StaticString) {
        emit(.init(level: level, message: message, file: file.description, line: UInt(max(0, line)), function: function.description))
    }
}
