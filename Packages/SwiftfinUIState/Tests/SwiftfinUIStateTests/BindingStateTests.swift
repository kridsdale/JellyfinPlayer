//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Combine
@testable import SwiftfinUIState
import SwiftUI
import XCTest

final class BindingStateTests: XCTestCase {
    @MainActor
    private final class Cell<T> {
        var value: T
        init(_ value: T) {
            self.value = value
        }

        var binding: Binding<T> {
            Binding(get: { self.value }, set: { self.value = $0 })
        }
    }

    @MainActor
    func testClampedBindingReadsAndWritesInsideSliderRange() {
        let source = Cell(140)
        let bounded = source.binding.clamp(min: 0, max: 100)
        XCTAssertEqual(bounded.wrappedValue, 100)
        bounded.wrappedValue = -20
        XCTAssertEqual(source.value, 0)
        bounded.wrappedValue = 150
        XCTAssertEqual(source.value, 100)
        bounded.wrappedValue = 35
        XCTAssertEqual(source.value, 35)
    }

    @MainActor
    func testOptionalEditorBindingDoesNotWriteItsFallbackUntilEdited() {
        let source = Cell<String?>(nil)
        let field = source.binding.coalesce("Default")
        XCTAssertEqual(field.wrappedValue, "Default")
        XCTAssertNil(source.value)
        field.wrappedValue = "Edited"
        XCTAssertEqual(source.value, "Edited")
    }

    @MainActor
    func testSetTogglePreservesOtherSelectedIndicators() {
        let source = Cell(Set(["progress"]))
        let favorite = source.binding.contains("favorite")
        XCTAssertFalse(favorite.wrappedValue)
        favorite.wrappedValue = true
        favorite.wrappedValue = true
        XCTAssertEqual(source.value, Set(["progress", "favorite"]))
        favorite.wrappedValue = false
        XCTAssertEqual(source.value, Set(["progress"]))
    }

    @MainActor
    func testPublishedBoxWritesThroughToSourceAndPublishesOnItsOwner() {
        let source = Cell(2)
        let box = PublishedBox(source: source.binding)
        var values: [Int] = []
        let observation = box.$value.sink { values.append($0) }
        XCTAssertEqual(box.value, 2)
        box.value = 9
        XCTAssertEqual(source.value, 9)
        XCTAssertEqual(values, [2, 9])
        withExtendedLifetime(observation) {}
    }
}
