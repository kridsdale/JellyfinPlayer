//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation
import SwiftfinAccountModels
@testable import SwiftfinConnectivity
import Testing

@MainActor
private final class FakePathDriver: NetworkPathDriving {
    let snapshots: AsyncStream<NetworkPathSnapshot>
    private let continuation: AsyncStream<NetworkPathSnapshot>.Continuation
    private var sequence: UInt64 = 0
    private(set) var cancellationCount = 0
    init() {
        let pair = AsyncStream<NetworkPathSnapshot>.makeStream()
        snapshots = pair.stream
        continuation = pair.continuation
    }

    func send(satisfied: Bool = true, interface: ServerConnection.Interface, sequence explicit: UInt64? = nil) {
        sequence = explicit ?? sequence + 1
        continuation.yield(.init(sequence: sequence, isSatisfied: satisfied, interface: interface))
    }

    func cancel() {
        cancellationCount += 1
        continuation.finish()
    }
}

/// Deliberately ignores cancellation so late native completion is exercised.
private actor DeferredSSID {
    private var nextID = 0
    private var requests: [Int: CheckedContinuation<String?, Never>] = [:]
    var requestCount: Int {
        nextID
    }

    func fetch() async -> String? {
        nextID += 1
        let id = nextID
        return await withCheckedContinuation { requests[id] = $0 }
    }

    func finish(_ id: Int, ssid: String?) {
        requests.removeValue(forKey: id)?.resume(returning: ssid)
    }
}

@MainActor
private final class Recorder {
    private(set) var received: [NetworkConnectionContext] = []
    private(set) var ended = false
    private var task: Task<Void, Never>?
    init(values: AsyncStream<NetworkConnectionContext>) {
        task = Task { [weak self] in
            for await value in values {
                self?.received.append(value)
            }
            self?.ended = true
        }
    }

    isolated deinit { task?.cancel() }
}

private struct ObservationDeadline: Error {}
@MainActor
private func eventually(_ predicate: @MainActor () async -> Bool) async throws {
    let clock = ContinuousClock()
    let deadline = clock.now + .seconds(3)
    while await !predicate() {
        guard clock.now < deadline else { throw ObservationDeadline() }
        try await Task.sleep(for: .milliseconds(2))
    }
}

@Suite(.serialized)
@MainActor
struct ConnectivityContracts {
    @Test
    func `unsatisfied and non wifi do not fetch SSID`() async throws {
        let driver = FakePathDriver()
        let lookup = DeferredSSID()
        let observation = NetworkContextObservation(driver: driver, lookupSSID: { await lookup.fetch() })
        let recorder = Recorder(values: observation.values)
        driver.send(satisfied: false, interface: .wifi)
        try await eventually { recorder.received.count == 1 }
        driver.send(interface: .cellular)
        try await eventually { recorder.received.count == 2 }
        driver.send(interface: .any)
        try await eventually { recorder.received.count == 3 }
        #expect(await lookup.requestCount == 0)
        #expect(recorder.received.map(\.interface) == [.wifi, .cellular, .any])
        #expect(!recorder.received[0].isSatisfied)
        #expect(recorder.received.allSatisfy { $0.wifiSSID == nil })
        observation.cancel()
        try await eventually { recorder.ended }
        #expect(driver.cancellationCount == 1)
    }

    @Test
    func `wifi result is normalized and missing SSID remains unknown`() async throws {
        let driver = FakePathDriver()
        let lookup = DeferredSSID()
        let observation = NetworkContextObservation(driver: driver, lookupSSID: { await lookup.fetch() })
        let recorder = Recorder(values: observation.values)
        driver.send(interface: .wifi)
        try await eventually { await lookup.requestCount == 1 }
        await lookup.finish(1, ssid: "  Home\n")
        try await eventually { recorder.received.count == 1 }
        #expect(recorder.received[0].wifiSSID == "Home")
        driver.send(interface: .wifi)
        try await eventually { await lookup.requestCount == 2 }
        await lookup.finish(2, ssid: " \n")
        try await eventually { recorder.received.count == 2 }
        #expect(recorder.received[1].wifiSSID == nil)
        #expect(recorder.received[1].isSatisfied)
        observation.cancel()
    }

    @Test
    func `slow wifi lookup cannot replace new cellular path`() async throws {
        let driver = FakePathDriver()
        let lookup = DeferredSSID()
        let observation = NetworkContextObservation(driver: driver, lookupSSID: { await lookup.fetch() })
        let recorder = Recorder(values: observation.values)
        driver.send(interface: .wifi)
        try await eventually { await lookup.requestCount == 1 }
        driver.send(interface: .cellular)
        try await eventually { recorder.received.count == 1 }
        await lookup.finish(1, ssid: "Old Wi-Fi")
        observation.cancel()
        try await eventually { recorder.ended }
        #expect(recorder.received == [.init(isSatisfied: true, interface: .cellular, wifiSSID: nil)])
    }

    @Test
    func `overlapping wifi lookups keep latest receipt`() async throws {
        let driver = FakePathDriver()
        let lookup = DeferredSSID()
        let observation = NetworkContextObservation(driver: driver, lookupSSID: { await lookup.fetch() })
        let recorder = Recorder(values: observation.values)
        driver.send(interface: .wifi)
        try await eventually { await lookup.requestCount == 1 }
        driver.send(interface: .wifi)
        try await eventually { await lookup.requestCount == 2 }
        await lookup.finish(2, ssid: "New")
        try await eventually { recorder.received.count == 1 }
        await lookup.finish(1, ssid: "Old")
        observation.cancel()
        try await eventually { recorder.ended }
        #expect(recorder.received.map(\.wifiSSID) == ["New"])
    }

    @Test
    func `cancel stops driver and rejects delayed SSID`() async throws {
        let driver = FakePathDriver()
        let lookup = DeferredSSID()
        let observation = NetworkContextObservation(driver: driver, lookupSSID: { await lookup.fetch() })
        let recorder = Recorder(values: observation.values)
        driver.send(interface: .wifi)
        try await eventually { await lookup.requestCount == 1 }
        observation.cancel()
        observation.cancel()
        await lookup.finish(1, ssid: "Late")
        driver.send(interface: .cellular)
        try await eventually { recorder.ended }
        #expect(recorder.received.isEmpty)
        #expect(driver.cancellationCount == 1)
    }

    @Test
    func `releasing lease stops native observation without retaining owner`() async throws {
        let driver = FakePathDriver()
        let lookup = DeferredSSID()
        var observation: NetworkContextObservation? = .init(driver: driver, lookupSSID: { await lookup.fetch() })
        weak let weakObservation = observation
        let recorder = try Recorder(values: #require(observation).values)
        driver.send(interface: .wifi)
        try await eventually { await lookup.requestCount == 1 }
        observation = nil
        #expect(weakObservation == nil)
        #expect(driver.cancellationCount == 1)
        await lookup.finish(1, ssid: "Late")
        try await eventually { recorder.ended }
        #expect(recorder.received.isEmpty)
    }

    @Test
    func `one shot returns first value and stops driver`() async {
        let driver = FakePathDriver()
        let observation = NetworkContextObservation(driver: driver, lookupSSID: { nil })
        let task = Task { await NetworkConnectivity.current(observation: observation) }
        driver.send(interface: .any)
        let value = await task.value
        #expect(value.isSatisfied)
        #expect(value.interface == .any)
        #expect(driver.cancellationCount == 1)
    }

    @Test
    func `cancelling one shot does not require another native event`() async {
        let driver = FakePathDriver()
        let observation = NetworkContextObservation(driver: driver, lookupSSID: { nil })
        let task = Task { await NetworkConnectivity.current(observation: observation) }
        await Task.yield()
        task.cancel()
        #expect(await task.value == .unavailable)
        #expect(driver.cancellationCount == 1)
    }

    @Test
    func `late or duplicate callback receipt cannot regress context`() async throws {
        let driver = FakePathDriver()
        let lookup = DeferredSSID()
        let observation = NetworkContextObservation(driver: driver, lookupSSID: { await lookup.fetch() })
        let recorder = Recorder(values: observation.values)
        driver.send(interface: .cellular, sequence: 3)
        try await eventually { recorder.received.count == 1 }
        driver.send(interface: .wifi, sequence: 2)
        driver.send(interface: .wifi, sequence: 3)
        driver.send(satisfied: false, interface: .any, sequence: 4)
        try await eventually { recorder.received.count == 2 }
        #expect(await lookup.requestCount == 0)
        #expect(recorder.received[1] == .unavailable)
        observation.cancel()
    }
}
