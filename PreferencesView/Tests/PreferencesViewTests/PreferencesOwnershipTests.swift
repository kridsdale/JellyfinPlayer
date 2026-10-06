//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

#if os(tvOS)
//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

// SPDX-License-Identifier: MPL-2.0
@testable import PreferencesView
import SwiftUI
import UIKit
import XCTest

@MainActor
final class PreferencesOwnershipTests: XCTestCase {
    private final class Counter { var value = 0 }

    func testCommandValueCrossesExecutorsAndExecutesOnItsUIOwner() async {
        let counter = Counter()
        let command = PressCommandAction(title: "Fixture", press: .playPause) {
            MainActor.preconditionIsolated()
            counter.value += 1
        }
        await Task.detached { await command.action() }.value
        XCTAssertEqual(counter.value, 1)
    }

    func testHostingDeliversRenderedPreferencesAndDispatchesOnlyMatchingPress() async throws {
        let counter = Counter()
        let controller = UIPreferencesHostingController {
            Text("Fixture").pressCommands {
                PressCommandAction(title: "Play", press: .playPause) { counter.value += 1 }
            }
        }
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.view.layoutIfNeeded()
        defer { window.isHidden = true
            window.rootViewController = nil
        }
        for _ in 0 ..< 150 {
            if !controller.configuredPressCommands.isEmpty {
                break
            }
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertEqual(controller.configuredPressCommands.count, 1)
        XCTAssertFalse(controller.performPressCommand(.leftArrow))
        XCTAssertEqual(counter.value, 0)
        XCTAssertTrue(controller.performPressCommand(.playPause))
        XCTAssertEqual(counter.value, 1)
    }

    func testCommandBuildersPreserveConditionalOrderingAndIndependentOwners() async {
        let first = Counter(), second = Counter()
        let actions = PressCommandsBuilder.buildBlock(
            PressCommandsBuilder.buildExpression(.init(title: "First", press: .select) { first.value += 1 }),
            PressCommandsBuilder.buildOptional(nil),
            PressCommandsBuilder.buildEither(second: [.init(title: "Second", press: .menu) { second.value += 1 }])
        )
        XCTAssertEqual(actions.map(\.press), [.select, .menu])
        await Task.detached { await actions[1].action() }.value
        XCTAssertEqual(first.value, 0)
        XCTAssertEqual(second.value, 1)
    }
}

#endif
