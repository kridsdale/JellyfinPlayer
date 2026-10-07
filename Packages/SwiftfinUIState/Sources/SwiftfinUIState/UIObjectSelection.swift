//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

/// Source-tagged UI selection changes; retirement belongs to its originating
/// object, so an old object's completion cannot clear a newer selection.
public enum UIObjectEvent<Object: AnyObject> {
    case activated(Object)
    case retired(Object)
}

extension UIObjectEvent: Sendable where Object: Sendable {}

@MainActor
public final class UIObjectSelection<Object: AnyObject> {
    public private(set) var current: Object?
    public init() {}

    public func apply(_ event: UIObjectEvent<Object>) {
        switch event {
        case let .activated(object): current = object
        case let .retired(object):
            guard current === object else { return }
            current = nil
        }
    }

    /// A surrounding navigation/account boundary explicitly clears selection.
    public func clear() {
        current = nil
    }
}
