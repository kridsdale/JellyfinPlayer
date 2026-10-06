//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import CoreStore
import Foundation

public struct StoredDataAddress: Hashable, Sendable {
    public let ownerID: String
    public let field: String
    public let key: String
    public init(ownerID: String, field: String, key: String) {
        self.ownerID = ownerID
        self.field = field
        self.key = key
    }
}

public extension SwiftfinDatabase {
    private func clause(_ address: StoredDataAddress) -> FetchChainBuilder<AnyStoredData> {
        From<AnyStoredData>().where(\.$ownerID == address.ownerID && \.$field == address.field && \.$key == address.key)
    }

    func read(_ address: StoredDataAddress) throws -> Data? {
        try requireOpen()
        let rows = try dataStack.fetchAll(clause(address))
        assert(rows.count < 2, "Duplicate stored address")
        return rows.first?.data
    }

    func write(_ data: Data, at address: StoredDataAddress) throws {
        try requireOpen()
        let filter = clause(address)
        try Self.write(data, at: address, filter: filter, stack: dataStack)
    }

    private nonisolated static func write(
        _ data: Data,
        at address: StoredDataAddress,
        filter: FetchChainBuilder<AnyStoredData>,
        stack: DataStack
    ) throws {
        try stack.perform { transaction in
            let rows = try transaction.fetchAll(filter)
            assert(rows.count < 2, "Duplicate stored address")
            if let row = rows.first {
                transaction.edit(row)?.data = data
            } else {
                let row = transaction.create(Into<AnyStoredData>())
                row.ownerID = address.ownerID
                row.field = address.field
                row.key = address.key
                row.data = data
            }
        }
    }

    func deleteAll(ownerID: String, field: String? = nil) throws {
        try requireOpen()
        let filter = field.map { value in From<AnyStoredData>().where(\.$ownerID == ownerID && \.$field == value) }
            ?? From<AnyStoredData>().where(\.$ownerID == ownerID)
        try Self.delete(filter, in: dataStack)
    }

    func delete(_ address: StoredDataAddress) throws {
        try requireOpen()
        let filter = clause(address)
        try Self.delete(filter, in: dataStack)
    }

    private nonisolated static func delete(_ filter: FetchChainBuilder<AnyStoredData>, in stack: DataStack) throws {
        try stack.perform { transaction in try transaction.delete(transaction.fetchAll(filter)) }
    }

    func observe(
        _ address: StoredDataAddress,
        defaultData: Data,
        onChange: @escaping @MainActor @Sendable () -> Void
    ) throws -> StoredDataObservation {
        try requireOpen()
        if try dataStack.fetchOne(clause(address)) == nil {
            try write(defaultData, at: address)
        }
        guard let row = try dataStack.fetchOne(clause(address)) else { throw StoredDataError.observationUnavailable }
        return StoredDataObservation(publisher: row.asPublisher(in: dataStack), onChange: onChange)
    }
}

public enum StoredDataError: Error, Equatable { case observationUnavailable, openingInProgress, notOpen }

@MainActor
public final class StoredDataObservation {
    private let publisher: ObjectPublisher<AnyStoredData>
    private var active = true
    init(publisher: ObjectPublisher<AnyStoredData>, onChange: @escaping @MainActor @Sendable () -> Void) {
        self.publisher = publisher
        publisher.addObserver(self) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard self?.active == true else { return }
                onChange()
            }
        }
    }

    public func cancel() {
        guard active else { return }
        active = false
        publisher.removeObserver(self)
    }

    isolated deinit { publisher.removeObserver(self) }
}
