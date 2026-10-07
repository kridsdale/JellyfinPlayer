//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

#if canImport(UIKit)
import SwiftfinScrolling
import UIKit
import XCTest

@MainActor
final class ScrollOffsetUIKitContracts: XCTestCase {
    private final class ExistingDelegate: NSObject, UIScrollViewDelegate {}
    func testObservationPreservesExistingDelegateAndStopsAtDisconnect() {
        let view = UIScrollView(), delegate = ExistingDelegate(), observer = ScrollOffsetObserver()
        view.delegate = delegate
        var values: [CGFloat] = []
        observer.connect(view) { values.append($0) }
        view.contentOffset.y = 10
        XCTAssertTrue(view.delegate === delegate)
        XCTAssertEqual(values.last, 10)
        observer.disconnect()
        view.contentOffset.y = 20
        XCTAssertEqual(values.last, 10)
        XCTAssertTrue(view.delegate === delegate)
    }

    func testReplacementIgnoresPriorViewAndUsesLatestBinding() {
        let a = UIScrollView(), b = UIScrollView(), observer = ScrollOffsetObserver()
        var old: [CGFloat] = [], current: [CGFloat] = []
        observer.connect(a) { old.append($0) }
        observer.connect(b) { current.append($0) }
        a.contentOffset.y = 10
        b.contentOffset.y = 20
        XCTAssertTrue(old.isEmpty)
        XCTAssertEqual(current.last, 20)
        observer.connect(b) { current.append($0 + 100) }
        b.contentOffset.y = 30
        XCTAssertEqual(current.last, 130)
        observer.disconnect()
    }

    func testFinalOwnerReleaseRemovesNativeObservation() {
        let view = UIScrollView()
        var observer: ScrollOffsetObserver? = ScrollOffsetObserver()
        weak let weakObserver = observer
        var delivered = false
        observer?.connect(view) { _ in delivered = true }
        observer = nil
        XCTAssertNil(weakObserver)
        view.contentOffset.y = 40
        XCTAssertFalse(delivered)
    }
}
#endif
