//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import SwiftfinScrolling
import SwiftUI
@_spi(Advanced) import SwiftUIIntrospect

struct ScrollViewOffsetModifier: ViewModifier {
    @StateObject
    private var observer = ScrollOffsetObserver()
    let scrollViewOffset: Binding<CGFloat>

    func body(content: Content) -> some View {
        let binding = scrollViewOffset
        let observer = self.observer
        return content.introspect(.scrollView, on: .iOS(.v15...), .tvOS(.v15...)) { scrollView in
            observer.connect(scrollView) { offset in
                binding.wrappedValue = offset
            }
        }
    }
}
