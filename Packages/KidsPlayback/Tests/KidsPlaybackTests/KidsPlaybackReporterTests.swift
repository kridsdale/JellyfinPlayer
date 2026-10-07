//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import KidsPlayback
import Testing

@Test @MainActor
func `shared reporting queue compatibility`() async {
    let reporter = KidsPlaybackReporter(initial: 0) { _ in }
    reporter.finish(1)
    await reporter.waitUntilFinished()
}
