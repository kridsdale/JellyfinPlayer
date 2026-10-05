//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

// SPDX-License-Identifier: MPL-2.0
import Foundation

/// Account-scoped, memory-only artwork. A hit still requires an eligible image
/// owner, library and current tag; this cache never requests media or item lists.
public actor KidsArtworkCache {
    public typealias Fetch = @Sendable (KidsItem, Int) async throws -> Data
    private struct Key: Hashable {
        let owner: String
        let tag: String
        let width: Int
    }

    private struct Entry {
        let data: Data
        let expires: ContinuousClock.Instant
        var access: UInt64
    }

    private struct Flight {
        let id: UUID
        let generation: UUID
        let retentionGeneration: UUID
        let task: Task<Data, Error>
    }

    private let binding: KidsBinding
    private let fetch: Fetch
    private let lifetime: Duration
    private let byteLimit: Int
    private let entryLimit: Int
    private let gate = KidsArtworkRequestGate()
    private var entries: [Key: Entry] = [:]
    private var flights: [Key: Flight] = [:]
    private var retainedBytes = 0
    private var access: UInt64 = 0
    private var generation = UUID()
    private var retentionGeneration = UUID()

    public init(
        binding: KidsBinding,
        lifetime: Duration = .seconds(300),
        byteLimit: Int = 24 * 1024 * 1024,
        entryLimit: Int = 96,
        fetch: @escaping Fetch
    ) {
        self.binding = binding
        self.lifetime = lifetime
        self.byteLimit = max(0, byteLimit)
        self.entryLimit = max(1, entryLimit)
        self.fetch = fetch
    }

    public init(api: KidsAPI, binding: KidsBinding) {
        self.binding = binding
        lifetime = .seconds(300)
        byteLimit = 24 * 1024 * 1024
        entryLimit = 96
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.httpMaximumConnectionsPerHost = 4
        let session = URLSession(configuration: configuration)
        fetch = { item, width in
            let request = try api.imageRequest(for: item, binding: binding, width: width)
            let trace = KidsPerformance.begin(.http, endpoint: .artwork)
            do {
                let delegate = trace.map(KidsPerformanceTaskDelegate.init(span:))
                let (data, response) = try await session.data(for: request, delegate: delegate)
                guard let response = response as? HTTPURLResponse else { throw KidsAPIError.invalidResponse }
                trace?.mark(.response, values: ["bytes": Double(data.count), "status": Double(response.statusCode)])
                switch response.statusCode {
                case 200: break
                case 401, 403: throw KidsAPIError.authentication
                case 404: throw KidsAPIError.unavailable
                default: throw KidsAPIError.connection
                }
                guard !data.isEmpty, data.count <= 8 * 1024 * 1024 else { throw KidsAPIError.invalidResponse }
                trace?.finish()
                return data
            } catch {
                let failure: Error = Task.isCancelled || (error as? URLError)?.code == .cancelled ? CancellationError() : error
                trace?.finish(error: failure)
                throw failure
            }
        }
    }

    public func data(for item: KidsItem, binding expected: KidsBinding, width: Int = 600) async throws -> Data {
        try Task.checkCancellation()
        guard expected == binding, KidsEligibility.permits(item, binding: binding),
              let owner = item.imageOwnerID, !owner.isEmpty,
              let tag = item.imageTag, !tag.isEmpty,
              owner == item.id || (item.kind == .episode && owner == item.seriesID),
              (64 ... 1600).contains(width) else { throw KidsContractError.denied }
        let key = Key(owner: owner, tag: tag, width: width)
        let trace = KidsPerformance.begin(.artworkCache, endpoint: .artwork)
        var awaitedFlightID: UUID?
        do {
            access &+= 1
            if var entry = entries[key], entry.expires > .now {
                entry.access = access
                entries[key] = entry
                trace?.finish(values: ["cache_hit": 1, "cache_bytes": Double(retainedBytes)])
                return entry.data
            }
            remove(key)
            let flight: Flight
            let joined: Bool
            if let existing = flights[key] {
                flight = existing
                joined = true
            } else {
                // Bound waiting tasks as well as retained bytes and active requests.
                guard flights.count < 64 else { throw KidsAPIError.connection }
                let fetch = self.fetch, gate = self.gate
                flight = Flight(id: UUID(), generation: generation, retentionGeneration: retentionGeneration, task: Task {
                    try await gate.perform { try await fetch(item, width) }
                })
                flights[key] = flight
                joined = false
            }
            awaitedFlightID = flight.id
            let data = try await flight.task.value
            guard generation == flight.generation else { throw CancellationError() }
            if flights[key]?.id == flight.id {
                flights[key] = nil
                if flight.retentionGeneration == retentionGeneration, !data.isEmpty, data.count <= byteLimit {
                    entries[key] = Entry(data: data, expires: .now.advanced(by: lifetime), access: access)
                    retainedBytes += data.count
                    while entries.count > entryLimit || retainedBytes > byteLimit {
                        guard let oldest = entries.min(by: { $0.value.access < $1.value.access })?.key else { break }
                        remove(oldest)
                    }
                }
            }
            try Task.checkCancellation()
            trace?.finish(values: ["cache_hit": 0, "shared_wait": joined ? 1 : 0, "cache_bytes": Double(retainedBytes)])
            return data
        } catch {
            if let awaitedFlightID, flights[key]?.id == awaitedFlightID {
                flights[key] = nil
            }
            trace?.finish(error: error)
            throw error
        }
    }

    private func remove(_ key: Key) {
        if let removed = entries.removeValue(forKey: key) {
            retainedBytes -= removed.data.count
        }
    }

    /// Release retained bytes without revoking authorization or interrupting a
    /// shared visible load. Pre-warning flights may return, but cannot refill
    /// the cache; a subsequent request can populate it normally.
    public func trimForMemoryPressure() {
        retentionGeneration = UUID()
        entries.removeAll()
        retainedBytes = 0
    }

    public func invalidate() {
        generation = UUID()
        entries.removeAll()
        retainedBytes = 0
        for flight in flights.values {
            flight.task.cancel()
        }
        flights.removeAll()
    }
}

/// Four active loads across foreground and prefetch callers, including HTTP/2.
/// Cancellation removes a queued waiter and always returns an acquired permit.
private actor KidsArtworkRequestGate {
    private var active = 0
    private var waiting: [(UUID, CheckedContinuation<Void, Error>)] = []

    func perform<T: Sendable>(_ operation: @Sendable () async throws -> T) async throws -> T {
        try await acquire()
        defer { release() }
        try Task.checkCancellation()
        return try await operation()
    }

    private func acquire() async throws {
        try Task.checkCancellation()
        if active < 4 {
            active += 1
            return
        }
        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                if Task.isCancelled {
                    continuation.resume(throwing: CancellationError())
                } else {
                    waiting.append((id, continuation))
                }
            }
        } onCancel: {
            Task { await self.cancel(id) }
        }
    }

    private func cancel(_ id: UUID) {
        if let index = waiting.firstIndex(where: { $0.0 == id }) {
            waiting.remove(at: index).1.resume(throwing: CancellationError())
        }
    }

    private func release() {
        if waiting.isEmpty {
            active -= 1
        } else {
            waiting.removeFirst().1.resume()
        }
    }
}
