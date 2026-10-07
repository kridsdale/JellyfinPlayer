//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation

/// One actor owns flights and a bounded image LRU. Only supplied image loads run.
@MainActor
public final class PreviewImageCache<Image: Sendable> {
    public typealias Load = @MainActor @Sendable (Int) async -> Image?
    private struct Flight { let id: UUID
        let task: Task<Image?, Never>
        let order: UInt64
    }

    private struct Entry { let image: Image
        var access: UInt64
    }

    private let load: Load
    private let isCurrent: @MainActor @Sendable () -> Bool
    private let capacity: Int
    private let flightLimit: Int
    private var flights: [Int: Flight] = [:]
    private var entries: [Int: Entry] = [:]
    private var clock: UInt64 = 0
    private var generation = UUID()
    private var valid = true

    public init(
        capacity: Int = 16,
        flightLimit: Int = 4,
        isCurrent: @escaping @MainActor @Sendable () -> Bool,
        load: @escaping Load
    ) {
        self.capacity = max(1, capacity)
        self.flightLimit = max(1, flightLimit)
        self.isCurrent = isCurrent
        self.load = load
    }

    isolated deinit { for flight in flights.values {
        flight.task.cancel()
    } }
    public var isValid: Bool {
        if valid && !isCurrent() {
            invalidate()
        }
        return valid
    }

    public func invalidate() {
        valid = false
        generation = UUID()
        for flight in flights.values {
            flight.task.cancel()
        }
        flights.removeAll()
        entries.removeAll()
    }

    public func image(at index: Int) async -> Image? {
        guard index >= 0, isValid, !Task.isCancelled else { return nil }
        if var entry = entries[index] {
            clock &+= 1
            entry.access = clock
            entries[index] = entry
            return entry.image
        }
        let epoch = generation
        let flight = start(index, required: true)
        guard let flight else { return nil }
        let result = await flight.task.value
        guard !Task.isCancelled, isValid, generation == epoch else { return nil }
        return result
    }

    public func prefetch(_ indexes: [Int]) {
        guard isValid else { return }
        for index in indexes where index >= 0 && entries[index] == nil {
            _ = start(index, required: false)
        }
    }

    private func start(_ index: Int, required: Bool) -> Flight? {
        guard isValid else { return nil }
        if let flight = flights[index] {
            return flight
        }
        if flights.count >= flightLimit {
            guard required, let oldest = flights.min(by: { $0.value.order < $1.value.order }) else { return nil }
            oldest.value.task.cancel()
            flights.removeValue(forKey: oldest.key)
        }
        let epoch = generation, id = UUID(), load = self.load
        clock &+= 1
        let task = Task { [weak self] () -> Image? in
            guard !Task.isCancelled else { return nil }
            let image = await load(index)
            let result = Task.isCancelled ? nil : image
            self?.complete(index, id: id, generation: epoch, image: result)
            return result
        }
        let flight = Flight(id: id, task: task, order: clock)
        flights[index] = flight
        return flight
    }

    private func complete(_ index: Int, id: UUID, generation: UUID, image: Image?) {
        guard self.generation == generation, flights[index]?.id == id else { return }
        flights.removeValue(forKey: index)
        guard isValid, let image else { return }
        clock &+= 1
        entries[index] = Entry(image: image, access: clock)
        while entries.count > capacity {
            guard let oldest = entries.min(by: { $0.value.access < $1.value.access }) else { return }
            entries.removeValue(forKey: oldest.key)
        }
    }
}
