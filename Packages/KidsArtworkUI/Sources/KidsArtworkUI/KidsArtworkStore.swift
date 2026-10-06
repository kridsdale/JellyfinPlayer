//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

// SPDX-License-Identifier: MPL-2.0
import Combine
import KidsArtwork
import KidsCatalog
import KidsDiagnostics
import KidsDomain
import UIKit

/// Keeps prepared pixels on the main actor and downloads/decompression off it.
/// Replaced on account, token, server or approved-library changes; memory only.
@MainActor
public final class KidsArtworkStore {
    private struct Key: Hashable {
        let owner: String
        let tag: String
        let width: Int
    }

    private struct Entry {
        let image: UIImage
        let expires: ContinuousClock.Instant
        let cost: Int
        var access: UInt64
    }

    private struct Flight {
        let id: UUID
        let retentionGeneration: UUID
        let task: Task<UIImage, Error>
    }

    private let binding: KidsBinding
    private let bytes: KidsArtworkCache
    private var entries: [Key: Entry] = [:]
    private var flights: [Key: Flight] = [:]
    private var cost = 0
    private var access: UInt64 = 0
    private var valid = true
    private var retentionGeneration = UUID()
    private var memoryWarning: AnyCancellable?

    public convenience init(api: KidsAPI, binding: KidsBinding) {
        self.init(cache: KidsArtworkCache(api: api, binding: binding), binding: binding)
    }

    init(cache: KidsArtworkCache, binding: KidsBinding) {
        self.binding = binding
        bytes = cache
        memoryWarning = NotificationCenter.default.publisher(for: UIApplication.didReceiveMemoryWarningNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                MainActor.assumeIsolated { self?.trimForMemoryPressure() }
            }
    }

    public func image(for item: KidsItem, binding expected: KidsBinding, width: Int = 600) async throws -> UIImage {
        try Task.checkCancellation()
        guard valid, expected == binding, KidsEligibility.permits(item, binding: binding),
              let owner = item.imageOwnerID, let tag = item.imageTag, !tag.isEmpty,
              owner == item.id || (item.kind == .episode && owner == item.seriesID),
              (64 ... 1600).contains(width) else { throw KidsContractError.denied }
        let key = Key(owner: owner, tag: tag, width: width)
        access &+= 1
        if var entry = entries[key], entry.expires > .now {
            entry.access = access
            entries[key] = entry
            let trace = KidsPerformance.begin(.artworkCache, endpoint: .artwork)
            trace?.finish(values: ["cache_hit": 1, "cache_bytes": Double(cost)])
            return entry.image
        }
        remove(key)
        let flight: Flight
        if let existing = flights[key] {
            flight = existing
        } else {
            let bytes = self.bytes, binding = self.binding
            flight = Flight(id: UUID(), retentionGeneration: retentionGeneration, task: Task {
                let data = try await bytes.data(for: item, binding: binding, width: width)
                try Task.checkCancellation()
                let trace = KidsPerformance.begin(.decode, endpoint: .artwork)
                do {
                    guard let compressed = UIImage(data: data),
                          let prepared = await compressed.byPreparingForDisplay() else { throw KidsAPIError.invalidResponse }
                    try Task.checkCancellation()
                    trace?.finish()
                    return prepared
                } catch { trace?.finish(error: error)
                    throw error
                }
            })
            flights[key] = flight
        }
        do {
            let image = try await flight.task.value
            guard valid else { throw CancellationError() }
            if flights[key]?.id == flight.id {
                flights[key] = nil
                let imageCost = image.cgImage.map { $0.bytesPerRow * $0.height } ?? 0
                if flight.retentionGeneration == retentionGeneration, imageCost > 0, imageCost <= 48 * 1024 * 1024 {
                    entries[key] = Entry(image: image, expires: .now.advanced(by: .seconds(300)), cost: imageCost, access: access)
                    cost += imageCost
                    while entries.count > 64 || cost > 48 * 1024 * 1024 {
                        guard let oldest = entries.min(by: { $0.value.access < $1.value.access })?.key else { break }
                        remove(oldest)
                    }
                }
            }
            try Task.checkCancellation()
            return image
        } catch {
            if flights[key]?.id == flight.id {
                flights[key] = nil
            }
            throw error
        }
    }

    private func remove(_ key: Key) {
        if let removed = entries.removeValue(forKey: key) {
            cost -= removed.cost
        }
    }

    private func trimForMemoryPressure() {
        retentionGeneration = UUID()
        entries.removeAll()
        cost = 0
        // No revision change: visible SwiftUI images keep their pixels, and
        // memory pressure does not trigger an immediate grid-wide reload.
        Task { await bytes.trimForMemoryPressure() }
    }

    public func invalidate() {
        valid = false
        memoryWarning = nil
        entries.removeAll()
        cost = 0
        for flight in flights.values {
            flight.task.cancel()
        }
        flights.removeAll()
        Task { await bytes.invalidate() }
    }
}
