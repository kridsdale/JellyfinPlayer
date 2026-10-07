//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation

/// One current SVG payload/render. No native parser, view, disk or network access.
@MainActor
final class SVGRenderState<Rendered: AnyObject> {
    private var input: Data?
    private var revision = UUID()
    private(set) var rendered: Rendered?

    /// Return true when this call installed a changed input. Invalid/empty input
    /// clears previous output; identical input is memoized, including failures.
    @discardableResult
    func update(_ data: Data, make: (Data) -> Rendered?) -> Bool {
        guard input != data else { return false }
        input = data
        let ticket = UUID()
        revision = ticket
        rendered = nil
        let result = data.isEmpty ? nil : make(data)
        guard revision == ticket else { return false }
        rendered = result
        return true
    }

    func reset() {
        revision = UUID()
        input = nil
        rendered = nil
    }
}
