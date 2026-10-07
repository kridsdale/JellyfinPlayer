//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

// SPDX-License-Identifier: MPL-2.0
import SwiftfinAsyncStreams

/// Source compatibility for Kids callers; the shared reporting owner implements ordering.
public typealias KidsPlaybackReporter<Snapshot: Sendable> = CoalescingSessionQueue<Snapshot>
