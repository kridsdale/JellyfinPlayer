//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import KidsPlaybackSession
import SwiftUI

@MainActor
public protocol KidsPlaybackPresentation: AnyObject {
    func surface(for session: KidsPlaybackController) -> AnyView
    func tracks(for session: KidsPlaybackController, authorize: @escaping @MainActor () -> Bool) -> AnyView
}

/// Used only by internal synthetic previews; normal root construction requires the host renderer.
@MainActor
final class KidsPreviewPlaybackPresentation: KidsPlaybackPresentation {
    func surface(for session: KidsPlaybackController) -> AnyView {
        AnyView(EmptyView())
    }

    func tracks(for session: KidsPlaybackController, authorize: @escaping @MainActor () -> Bool) -> AnyView {
        AnyView(EmptyView())
    }
}
