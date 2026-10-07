//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation

/// One borrowed target and one observation retirement callback. Observer factories
/// and delivery run on the same actor; queued callbacks are generation-bound.
@MainActor
final class ScrollOffsetLease<Target: AnyObject> {
    private weak var target: Target?
    private var revision = UUID()
    private var retire: (@MainActor () -> Void)?
    private var receive: (@MainActor (CGFloat) -> Void)?

    func connect(
        _ target: Target,
        receive: @escaping @MainActor (CGFloat) -> Void,
        subscribe: (Target, @escaping @MainActor @Sendable (CGFloat) -> Void) -> @MainActor () -> Void
    ) {
        if self.target === target {
            self.receive = receive
            return
        }
        let ticket = UUID()
        revision = ticket
        self.target = target
        self.receive = receive
        let previous = retire
        retire = nil
        previous?()
        // Retirement may synchronously install a newer connection.
        guard revision == ticket, self.target === target else { return }
        let delivery: @MainActor @Sendable (CGFloat) -> Void = { [weak self, weak target] value in
            guard let self, let target, self.target === target, self.revision == ticket else { return }
            self.receive?(value)
        }
        let cleanup = subscribe(target, delivery)
        guard revision == ticket, self.target === target else {
            cleanup()
            return
        }
        retire = cleanup
    }

    func disconnect() {
        revision = UUID()
        target = nil
        receive = nil
        let cleanup = retire
        retire = nil
        cleanup?()
    }

    isolated deinit {
        retire?()
    }
}
