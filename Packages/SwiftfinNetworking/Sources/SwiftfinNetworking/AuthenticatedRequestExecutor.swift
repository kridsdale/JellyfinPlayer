//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation
import Get

/// Value/command transport for feature owners. No SDK client or credentials escape.
@MainActor
public protocol JellyfinRequestSending {
    func value<Value: Decodable & Sendable>(for request: Request<Value>) async throws -> Value
    func complete(_ request: Request<Void>) async throws
}

extension JellyfinTransport: JellyfinRequestSending {
    public func value<Value: Decodable & Sendable>(for request: Request<Value>) async throws -> Value {
        try await send(request).value
    }

    public func complete(_ request: Request<Void>) async throws {
        try await send(request)
    }
}

/// Captures one transport and rejects work after its account/connection binding expires.
@MainActor
public final class AuthenticatedRequestExecutor {
    private let sender: any JellyfinRequestSending
    private let isCurrent: @MainActor @Sendable () -> Bool
    public init(sender: any JellyfinRequestSending, isCurrent: @escaping @MainActor @Sendable () -> Bool = { true }) {
        self.sender = sender
        self.isCurrent = isCurrent
    }

    public func checkBinding() throws {
        try Task.checkCancellation()
        guard isCurrent() else { throw CancellationError() }
    }

    public func value<Value: Decodable & Sendable>(for request: Request<Value>) async throws -> Value {
        try checkBinding()
        do {
            let value = try await sender.value(for: request)
            try checkBinding()
            return value
        } catch {
            try checkBinding()
            throw error
        }
    }

    public func complete(_ request: Request<Void>) async throws {
        try checkBinding()
        do {
            try await sender.complete(request)
            try checkBinding()
        } catch {
            try checkBinding()
            throw error
        }
    }
}
