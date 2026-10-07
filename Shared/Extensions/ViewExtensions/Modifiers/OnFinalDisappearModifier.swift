//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import SwiftfinUIState
import SwiftUI

struct OnFinalDisappearModifier: ViewModifier {

    @StateObject
    private var observer: ViewLifetimeObserver

    init(action: @escaping @MainActor () -> Void) {
        _observer = StateObject(wrappedValue: ViewLifetimeObserver(onEnd: action))
    }

    func body(content: Content) -> some View {
        content
            .background {
                Color.clear
            }
    }
}
