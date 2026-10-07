//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Combine

/// A view-owned lifetime. Final release invokes its callback on the UI actor,
/// including when the final strong reference is dropped on a foreign executor.
@MainActor
public final class ViewLifetimeObserver: ObservableObject {
    private let onEnd: @MainActor () -> Void

    public init(onEnd: @escaping @MainActor () -> Void) {
        self.onEnd = onEnd
    }

    isolated deinit {
        onEnd()
    }
}
