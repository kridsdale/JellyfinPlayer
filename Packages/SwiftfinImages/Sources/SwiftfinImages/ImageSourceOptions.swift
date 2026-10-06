//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation

public protocol WithImageSourceOptions {
    var maxWidth: CGFloat? { get set }
    var maxHeight: CGFloat? { get set }
    var quality: Int? { get set }
}

public struct ImageSourceOptions: WithImageSourceOptions, Sendable {
    public var maxWidth: CGFloat?
    public var maxHeight: CGFloat?
    public var quality: Int?
    public init(maxWidth: CGFloat? = nil, maxHeight: CGFloat? = nil, quality: Int? = 90) {
        self.maxWidth = maxWidth
        self.maxHeight = maxHeight
        self.quality = quality
    }
}
