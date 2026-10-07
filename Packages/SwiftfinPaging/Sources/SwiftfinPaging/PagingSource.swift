//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation

public struct PagingRequest: Sendable, Equatable, CustomStringConvertible, CustomDebugStringConvertible {
    public let offset: Int
    public let limit: Int
    public let query: String?
    public init(offset: Int, limit: Int, query: String? = nil) {
        self.offset = offset
        self.limit = limit
        self.query = query
    }

    public var description: String {
        "PagingRequest(offset: \(offset), limit: \(limit), query: <redacted>)"
    }

    public var debugDescription: String {
        description
    }
}

/// A page can consume more server rows than it displays after filtering.
@MainActor
public struct PagingPage<Element> {
    public let items: [Element]
    public let consumedCount: Int
    public init(items: [Element], consumedCount: Int? = nil) {
        self.items = items
        self.consumedCount = max(items.count, consumedCount ?? items.count)
    }
}

/// Composition binds these ports to an exact account/transport and immutable query inputs.
@MainActor
public struct PagingSource<Element> {
    public typealias Load = @MainActor @Sendable (PagingRequest) async throws -> PagingPage<Element>
    public let identity: UUID
    public let canPage: Bool
    public let load: Load
    public let search: Load?
    public let random: (@MainActor @Sendable () async throws -> Element?)?
    public let isCurrent: @MainActor @Sendable () -> Bool
    public init(
        identity: UUID,
        canPage: Bool = true,
        isCurrent: @escaping @MainActor @Sendable () -> Bool,
        load: @escaping Load,
        search: Load? = nil,
        random: (@MainActor @Sendable () async throws -> Element?)? = nil
    ) {
        self.identity = identity
        self.canPage = canPage
        self.isCurrent = isCurrent
        self.load = load
        self.search = search
        self.random = random
    }
}
