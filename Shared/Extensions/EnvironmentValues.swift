//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import SwiftUI

extension EnvironmentValues {

    @Entry
    var posterConfiguration: PosterConfiguration = .default

    @Entry
    var audioOffset: Binding<Duration> = .constant(.zero)

    @Entry
    var frameForParentView: [CoordinateSpace: FrameAndSafeAreaInsets] = [:]

    @Entry
    var isEditing: Bool = false

    @Entry
    var isHighlighted: Bool = true

    @Entry
    var isSelected: Bool = false

    @Entry
    var playbackSpeed: Binding<Double> = .constant(1)

    @Entry
    var posterDisplayType: PosterDisplayType = .portrait

    @Entry
    // The presenting media route injects its measured safe area. An environment
    // default must not reach into main-actor UIKit from arbitrary readers.
    var safeAreaInsets: EdgeInsets = .zero

    @Entry
    var subtitleOffset: Binding<Duration> = .constant(.zero)

    @Entry
    var tabSafeAreaInsets: EdgeInsets = .zero

    // TODO: figure out this directional response stuff
    @Entry
    var panGestureDirection: Direction = .all
}
