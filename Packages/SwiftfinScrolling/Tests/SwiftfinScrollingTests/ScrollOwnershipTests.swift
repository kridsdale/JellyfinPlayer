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
final class ScrollOwnershipTests: XCTestCase {
    private final class View: UIScrollView {
        var commands = 0
        override func setContentOffset(_ contentOffset: CGPoint, animated: Bool) {
            commands += 1
            super.setContentOffset(contentOffset, animated: animated)
        }
    }

    private func view() -> View {
        let view = View(frame: CGRect(x: 0, y: 0, width: 400, height: 200))
        view.contentSize = CGSize(width: 2000, height: 2000)
        return view
    }

    func testHorizontalSyncIsBidirectionalAndPreservesVerticalOffset() {
        let proxy = EPGScrollProxy(), content = view(), header = view()
        proxy.registerContent(content, centeringOn: nil)
        proxy.registerHorizontal(header)
        content.setContentOffset(CGPoint(x: 120, y: 40), animated: false)
        XCTAssertEqual(header.contentOffset, CGPoint(x: 120, y: 0))
        header.setContentOffset(CGPoint(x: 240, y: 12), animated: false)
        XCTAssertEqual(content.contentOffset, CGPoint(x: 240, y: 40))
        proxy.disconnect()
    }

    func testVerticalSyncPreservesHorizontalOffset() {
        let proxy = EPGScrollProxy(), content = view(), sidebar = view()
        sidebar.contentOffset = CGPoint(x: 17, y: 0)
        proxy.registerVertical(content)
        proxy.registerVertical(sidebar)
        content.setContentOffset(CGPoint(x: 30, y: 110), animated: false)
        XCTAssertEqual(sidebar.contentOffset, CGPoint(x: 17, y: 110))
        sidebar.setContentOffset(CGPoint(x: 17, y: 220), animated: false)
        XCTAssertEqual(content.contentOffset, CGPoint(x: 30, y: 220))
        proxy.disconnect()
    }

    func testDisconnectRejectsChangesAndReconnectCreatesCurrentObservers() {
        let proxy = EPGScrollProxy(), content = view(), header = view()
        proxy.registerContent(content, centeringOn: nil)
        proxy.registerHorizontal(header)
        content.contentOffset.x = 50
        XCTAssertEqual(header.contentOffset.x, 50)
        proxy.disconnect()
        content.contentOffset.x = 100
        XCTAssertEqual(header.contentOffset.x, 50)
        proxy.connect()
        content.contentOffset.x = 150
        XCTAssertEqual(header.contentOffset.x, 150)
        proxy.disconnect()
    }

    func testCenteringOccursOncePerContentAndResetAllowsRecenter() {
        let proxy = EPGScrollProxy(), first = view(), second = view()
        proxy.registerContent(first, centeringOn: 1000)
        XCTAssertEqual(first.contentOffset.x, 800)
        proxy.registerContent(first, centeringOn: 1200)
        XCTAssertEqual(first.contentOffset.x, 800)
        proxy.registerContent(second, centeringOn: 1200)
        XCTAssertEqual(second.contentOffset.x, 1000)
        second.contentOffset.y = 30
        proxy.reset()
        XCTAssertEqual(second.contentOffset, CGPoint(x: 0, y: 30))
        proxy.registerContent(second, centeringOn: 300)
        XCTAssertEqual(second.contentOffset.x, 100)
        proxy.disconnect()
    }

    func testToleranceAndDuplicateRegistrationPreventRecursion() {
        let proxy = EPGScrollProxy(), content = view(), header = view()
        proxy.registerHorizontal(content)
        proxy.registerHorizontal(header)
        proxy.registerHorizontal(header)
        content.contentOffset.x = 0.5
        XCTAssertEqual(header.contentOffset.x, 0)
        XCTAssertEqual(header.commands, 0)
        content.contentOffset.x = 1
        XCTAssertEqual(header.contentOffset.x, 1)
        XCTAssertEqual(header.commands, 1)
        proxy.disconnect()
    }

    func testNativeObserversDoNotRetainCoordinatorAfterRelease() {
        let content = view(), header = view()
        var proxy: EPGScrollProxy? = EPGScrollProxy()
        weak let weakProxy = proxy
        proxy?.registerHorizontal(content)
        proxy?.registerHorizontal(header)
        proxy = nil
        XCTAssertNil(weakProxy)
        content.contentOffset.x = 200
        XCTAssertEqual(header.contentOffset.x, 0)
    }
}
#endif
