//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Defaults
import Foundation
import SwiftUI

extension VideoPlayer.PlaybackControls {

    enum JumpDirection {
        case forward
        case backward
    }

    func startSpeedBoost() {
        guard !isSpeedBoosting else { return }

        speedBoostTask = Task { @MainActor [self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            isSpeedBoosting = true
            containerState.originalPlaybackRate = manager.rate

            let multiplier = Defaults[.VideoPlayer.Gesture.longPressSpeedMultiplier]
            await manager.setRate(rate: multiplier.rawValue)

            toaster.present(
                Text(multiplier.displayTitle),
                systemName: "forward.fill"
            )
        }
    }

    func stopSpeedBoost(performJump: Bool = false) {
        speedBoostTask?.cancel()
        speedBoostTask = nil

        if isSpeedBoosting {
            if let originalRate = containerState.originalPlaybackRate {
                manager.setRate(rate: originalRate)

                toaster.present(
                    Text(originalRate, format: .playbackRate),
                    systemName: "forward.fill"
                )
            }

            containerState.originalPlaybackRate = nil
            isSpeedBoosting = false
            return
        }

        if performJump {
            jumpForward()
        }
    }

    func jumpForward() {
        containerState.jumpProgressObserver.jumpForward()
        toaster.present(
            Text(
                jumpForwardInterval.rawValue * containerState.jumpProgressObserver.jumps,
                format: .minuteSecondsAbbreviated
            ),
            systemName: "goforward"
        )
        scheduleJump(direction: .forward)
    }

    func jumpBackward() {
        containerState.jumpProgressObserver.jumpBackward()
        toaster.present(
            Text(
                jumpBackwardInterval.rawValue * containerState.jumpProgressObserver.jumps,
                format: .minuteSecondsAbbreviated
            ),
            systemName: "gobackward"
        )
        scheduleJump(direction: .backward)
    }

    func scheduleJump(direction: JumpDirection) {
        pendingJumpTask?.cancel()

        let jumpCount = containerState.jumpProgressObserver.jumps
        let interval = direction == .forward
            ? jumpForwardInterval.rawValue
            : jumpBackwardInterval.rawValue

        let work = Task { @MainActor [weak manager, weak containerState] in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            let totalDuration = interval * jumpCount

            switch direction {
            case .forward:
                manager?.proxy?.jumpForward(totalDuration)
            case .backward:
                manager?.proxy?.jumpBackward(totalDuration)
            }
            containerState?.jumpProgressObserver.reset()
        }

        pendingJumpTask = work
    }
}
