//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import KidsApplication
import SwiftUI

#if DEBUG
#Preview("Shows - missing art and focus") { KidsRootView(previewScenario: "shows") }
#Preview("Movies - posters") { KidsRootView(previewScenario: "movies") }
#Preview("Authorization denied - prior catalog hidden") { KidsRootView(previewScenario: "denied") }
#Preview("Offline catalog - protected help") { KidsRootView(previewScenario: "offline") }
#Preview("Neutral loading") { KidsRootView(previewScenario: "loading") }
#Preview("Empty catalog") { KidsRootView(previewScenario: "empty") }
#Preview("Ordered series finished") { KidsTitleView(
    model: KidsAppModel.preview("again"),
    item: KidsAppModel.preview("again").catalog[.shows]![0]
) }
#Preview("Movie resume") { KidsTitleView(
    model: KidsAppModel.preview("resume"),
    item: KidsAppModel.preview("resume").catalog[.movies]![0]
) }
#Preview("One episode show") { KidsRootView(previewScenario: "one-episode") }
#Preview("Movie completed") { KidsRootView(previewScenario: "movie-complete") }
#Preview("Movie paused - parent restart") { KidsRootView(previewScenario: "movie-paused") }
#Preview("Player paused timeline") { KidsRootView(previewScenario: "paused") }
#Preview("Player hidden controls") { KidsRootView(previewScenario: "hidden-player") }
#Preview("Next episode countdown") { KidsRootView(previewScenario: "countdown") }
#Preview("Player reconnecting") { KidsRootView(previewScenario: "reconnecting") }
#Preview("Session end with artwork") { KidsRootView(previewScenario: "session-end") }
#Preview("Parent gate") { KidsParentView(model: KidsAppModel.preview("shows")) }
#endif
