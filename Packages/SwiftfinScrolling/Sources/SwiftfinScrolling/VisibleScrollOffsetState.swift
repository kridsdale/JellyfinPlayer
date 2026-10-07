//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Combine
import Foundation

@MainActor
public final class VisibleScrollOffsetState {

    public init() {}

    private let visibleLeadingOffsetSubject = CurrentValueSubject<CGFloat, Never>(0)

    public var visibleLeadingOffset: CGFloat {
        visibleLeadingOffsetSubject.value
    }

    public var visibleLeadingOffsetPublisher: AnyPublisher<CGFloat, Never> {
        visibleLeadingOffsetSubject.eraseToAnyPublisher()
    }

    public func update(visibleLeadingOffset: CGFloat) {
        guard abs(self.visibleLeadingOffset - visibleLeadingOffset) > 0.5 else { return }
        visibleLeadingOffsetSubject.send(visibleLeadingOffset)
    }
}
