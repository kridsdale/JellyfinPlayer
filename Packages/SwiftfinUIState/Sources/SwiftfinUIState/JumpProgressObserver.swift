//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Combine
import Foundation

@MainActor
public final class JumpProgressObserver: ObservableObject {

    private let interval: TimeInterval
    public let timer: PokeIntervalTimer
    private var timerCancellable: AnyCancellable?

    public private(set) var jumps: Int = 0
    private var isForward = true

    public convenience init(interval: TimeInterval = 2) {
        self.init(interval: interval, timer: PokeIntervalTimer(defaultInterval: interval))
    }

    init(interval: TimeInterval, timer: PokeIntervalTimer) {
        self.interval = interval
        self.timer = timer

        timerCancellable = timer
            .sink { [weak self] _ in
                guard let self else { return }
                self.jumps = 0
            }
    }

    isolated deinit {
        timerCancellable?.cancel()
    }

    public func reset() {
        jumps = 0
    }

    public func jumpForward(interval: TimeInterval? = nil) {
        if isForward {
            jumps += 1
        } else {
            jumps = 1
            isForward = true
        }

        timer.poke(interval: interval ?? self.interval)
    }

    public func jumpBackward(interval: TimeInterval? = nil) {
        if !isForward {
            jumps += 1
        } else {
            jumps = 1
            isForward = false
        }

        timer.poke(interval: interval ?? self.interval)
    }
}
