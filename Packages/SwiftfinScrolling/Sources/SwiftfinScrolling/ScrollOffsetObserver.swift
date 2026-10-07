//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

#if canImport(UIKit)
import Combine
import Foundation
import UIKit

/// Borrowed scroll observation without changing the scroll view's own delegate.
@MainActor
public final class ScrollOffsetObserver: ObservableObject {
    private let lease = ScrollOffsetLease<UIScrollView>()

    public init() {}

    public func connect(_ scrollView: UIScrollView, onChange: @escaping @MainActor (CGFloat) -> Void) {
        lease.connect(scrollView, receive: onChange) { scrollView, receive in
            let readCurrent: @MainActor @Sendable () -> Void = { [weak scrollView] in
                guard let scrollView else { return }
                receive(scrollView.contentOffset.y)
            }
            let token = scrollView.observe(\.contentOffset, options: [.new], changeHandler: Self.handler(readCurrent))
            return { token.invalidate() }
        }
    }

    public func disconnect() {
        lease.disconnect()
    }

    // UIKit normally delivers synchronously on its owner. The foreign KVO closure
    // is formed outside actor isolation; fallback delivery reads current geometry
    // on the UI actor rather than transferring an SDK object or old position.
    private nonisolated static func handler(
        _ receive: @escaping @MainActor @Sendable () -> Void
    ) -> @Sendable (UIScrollView, NSKeyValueObservedChange<CGPoint>) -> Void {
        { _, _ in
            if Thread.isMainThread {
                MainActor.assumeIsolated { receive() }
            } else {
                Task { @MainActor in receive() }
            }
        }
    }
}
#endif
