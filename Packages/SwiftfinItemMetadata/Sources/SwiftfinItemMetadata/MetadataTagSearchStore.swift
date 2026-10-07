//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation

/// A single actor owns tag cache, binding replacement and shared loads.
@MainActor
public final class MetadataTagSearchStore {
    private var client: ItemMetadataClient?
    private var generation = UUID()
    private var loaded = false
    private var values: [String: String] = [:]
    private var flight: (id: UUID, task: Task<[String], any Error>)?
    public init() {}
    public func invalidate() {
        generation = UUID()
        flight?.task.cancel()
        flight = nil
        client = nil
        loaded = false
        values = [:]
    }

    private func bind(_ incoming: ItemMetadataClient) throws {
        try incoming.checkBinding()
        if client?.bindingID != incoming.bindingID {
            invalidate()
            client = incoming
        }
    }

    public func add(_ tags: [String], client: ItemMetadataClient) throws {
        try bind(client)
        for tag in tags {
            values[tag.localizedLowercase] = tag
        }
    }

    public func search(prefix: String, client incoming: ItemMetadataClient) async throws -> [String] {
        try bind(incoming)
        let revision = generation
        if !loaded {
            let current: (id: UUID, task: Task<[String], any Error>)
            if let flight {
                current = flight
            } else {
                current = (UUID(), Task { try await incoming.tags() })
                flight = current
            }
            do {
                let tags = try await current.task.value
                try Task.checkCancellation()
                try incoming.checkBinding()
                guard revision == generation, client?.bindingID == incoming.bindingID else { throw CancellationError() }
                if !loaded {
                    for tag in tags where values[tag.localizedLowercase] == nil {
                        values[tag.localizedLowercase] = tag
                    }
                    loaded = true
                }
                if flight?.id == current.id {
                    flight = nil
                }
            } catch {
                try Task.checkCancellation()
                try incoming.checkBinding()
                guard revision == generation else { throw CancellationError() }
                if flight?.id == current.id {
                    flight = nil
                }
                throw error
            }
        }
        try incoming.checkBinding()
        try Task.checkCancellation()
        guard revision == generation else { throw CancellationError() }
        guard !prefix.isEmpty else { return [] }
        let key = prefix.localizedLowercase
        return values.keys.filter { $0.hasPrefix(key) }.sorted().compactMap { values[$0] }
    }
}
