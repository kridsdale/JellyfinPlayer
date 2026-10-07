//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Combine
import Foundation
import SwiftUI

/// Observable wall-clock presentation. Native scheduling stays on the UI actor;
/// releasing the wrapper's owner cancels its run-loop subscription.
@MainActor
@propertyWrapper
public struct CurrentDate: @MainActor DynamicProperty {
    @ObservedObject
    private var observable: CurrentDateObserver

    public var projectedValue: Binding<Date> {
        $observable.currentDate
    }

    public var wrappedValue: Date {
        observable.currentDate
    }

    public init(interval: TimeInterval = 1) {
        observable = CurrentDateObserver(interval: interval)
    }

    init(observer: CurrentDateObserver) {
        observable = observer
    }

    public mutating func update() {
        _observable.update()
    }
}

@MainActor
protocol CurrentDateScheduling {
    func subscribe(every interval: TimeInterval, tick: @escaping @MainActor () -> Void) -> AnyCancellable
}

@MainActor
private struct RunLoopDateScheduler: CurrentDateScheduling {
    func subscribe(every interval: TimeInterval, tick: @escaping @MainActor () -> Void) -> AnyCancellable {
        Timer.publish(every: interval, on: .main, in: .common)
            .autoconnect()
            .sink { _ in
                MainActor.preconditionIsolated()
                tick()
            }
    }
}

@MainActor
final class CurrentDateObserver: ObservableObject {
    @Published
    var currentDate: Date
    private let now: @MainActor () -> Date
    private var subscription: AnyCancellable?

    convenience init(interval: TimeInterval = 1) {
        self.init(interval: interval, now: { .now }, scheduler: RunLoopDateScheduler())
    }

    init(interval: TimeInterval = 1, now: @escaping @MainActor () -> Date, scheduler: any CurrentDateScheduling) {
        self.now = now
        currentDate = now()
        let interval = interval.isFinite && interval > 0 ? interval : 1
        subscription = scheduler.subscribe(every: interval) { [weak self] in
            self?.refresh()
        }
    }

    private func refresh() {
        currentDate = now()
    }

    isolated deinit { subscription?.cancel() }
}
