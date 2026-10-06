//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

// SPDX-License-Identifier: MPL-2.0
import XCTest

/// XCTest's teardown executor does not own UI state. Transfer this actor-owned
/// cleanup object rather than the non-Sendable XCTestCase across that boundary.
@MainActor
final class SimulatorApplicationCleanup {
    private let application: XCUIApplication
    init(_ application: XCUIApplication) {
        self.application = application
    }

    func stop() {
        application.terminate()
    }
}
