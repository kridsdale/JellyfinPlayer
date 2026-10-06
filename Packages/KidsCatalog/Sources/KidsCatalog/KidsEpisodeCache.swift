//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

// SPDX-License-Identifier: MPL-2.0
import Foundation
import KidsDiagnostics
import KidsDomain

/// A bounded, in-memory cache of verified episode metadata for one exact account and
/// library binding. It never stores streams and never authorizes playback; the chosen
/// item must still pass fresh authorization before a media provider is constructed.
public actor KidsEpisodeCache {
    public typealias Fetch = @Sendable (String) async throws -> [KidsItem]
    private struct Entry {
        let values: [KidsItem]
        let expires: ContinuousClock.Instant
        var access: UInt64
    }

    private struct Flight {
        let id: UUID
        let generation: UUID
        let task: Task<[KidsItem], Error>
    }

    private let binding: KidsBinding
    private let fetch: Fetch
    private let lifetime: Duration
    private let capacity: Int
    private var entries: [String: Entry] = [:]
    private var flights: [String: Flight] = [:]
    private var generation = UUID()
    private var access: UInt64 = 0

    public init(binding: KidsBinding, lifetime: Duration = .seconds(300), capacity: Int = 12, fetch: @escaping Fetch) {
        self.binding = binding
        self.lifetime = lifetime
        self.capacity = max(1, capacity)
        self.fetch = fetch
    }

    public init(api: KidsAPI, binding: KidsBinding) {
        self.binding = binding
        lifetime = .seconds(300)
        capacity = 12
        fetch = { try await api.episodes(showID: $0, binding: binding) }
    }

    public func episodes(for show: KidsItem, binding expected: KidsBinding) async throws -> [KidsItem] {
        try Task.checkCancellation()
        guard expected == binding, binding.isValid, show.kind == .series,
              KidsEligibility.permits(show, binding: binding) else { throw KidsContractError.denied }
        let trace = KidsPerformance.begin(.episodeCache)
        var awaitedFlightID: UUID?
        do {
            access &+= 1
            if var entry = entries[show.id], entry.expires > .now {
                entry.access = access
                entries[show.id] = entry
                trace?.finish(values: ["cache_hit": 1, "episodes": Double(entry.values.count)])
                return entry.values
            }
            entries[show.id] = nil
            let flight: Flight
            let joined: Bool
            if let existing = flights[show.id] {
                flight = existing
                joined = true
            } else {
                let fetch = self.fetch, id = show.id
                flight = Flight(id: UUID(), generation: generation, task: Task { try await fetch(id) })
                flights[show.id] = flight
                joined = false
            }
            awaitedFlightID = flight.id
            let values = try await flight.task.value
            guard generation == flight.generation else { throw CancellationError() }
            // Defend the cache itself against a mismatched or forged loader result.
            let eligible = try KidsEligibility.episodes(values, showID: show.id, binding: binding)
            guard eligible.count == values.count else { throw KidsContractError.denied }
            if flights[show.id]?.id == flight.id {
                flights[show.id] = nil
                access &+= 1
                entries[show.id] = Entry(values: eligible, expires: .now.advanced(by: lifetime), access: access)
                while entries.count > capacity, let oldest = entries.min(by: { $0.value.access < $1.value.access })?.key {
                    entries[oldest] = nil
                }
            }
            try Task.checkCancellation()
            trace?.finish(values: ["cache_hit": 0, "shared_wait": joined ? 1 : 0, "episodes": Double(eligible.count)])
            return eligible
        } catch {
            // A failed task cannot become a permanent failed cache entry. Do not remove
            // a newer generation's replacement flight when an old task unwinds.
            if let awaitedFlightID, flights[show.id]?.id == awaitedFlightID {
                flights[show.id] = nil
            }
            trace?.finish(error: error)
            throw error
        }
    }

    /// Background warming may join an existing request but never queues a
    /// second show's scan while another metadata flight is active. Foreground
    /// requests remain available immediately through episodes(for:binding:).
    public func prefetch(for show: KidsItem, binding expected: KidsBinding) async throws -> [KidsItem]? {
        try Task.checkCancellation()
        guard expected == binding, binding.isValid, show.kind == .series,
              KidsEligibility.permits(show, binding: binding) else { throw KidsContractError.denied }
        guard flights.isEmpty || flights[show.id] != nil else { return nil }
        return try await episodes(for: show, binding: expected)
    }

    public func invalidate() {
        generation = UUID()
        entries.removeAll()
        for flight in flights.values {
            flight.task.cancel()
        }
        flights.removeAll()
    }
}
