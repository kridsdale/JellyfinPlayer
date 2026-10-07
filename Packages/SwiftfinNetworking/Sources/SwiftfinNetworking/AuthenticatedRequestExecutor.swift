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
    func response<Value: Decodable & Sendable>(for request: Request<Value>) async throws -> JellyfinResponse<Value>
    func value<Value: Decodable & Sendable>(for request: Request<Value>, delegate: (any URLSessionDataDelegate)?) async throws -> Value
    func complete(_ request: Request<Void>, delegate: (any URLSessionDataDelegate)?) async throws
}

public struct JellyfinResponse<Value: Sendable>: Sendable {
    public let value: Value
    public let responseURL: URL?
    public init(value: Value, responseURL: URL? = nil) {
        self.value = value
        self.responseURL = responseURL
    }
}

public extension JellyfinRequestSending {
    func response<Value: Decodable & Sendable>(for request: Request<Value>) async throws -> JellyfinResponse<Value> {
        try await .init(value: value(for: request))
    }

    func value<Value: Decodable & Sendable>(for request: Request<Value>, delegate: (any URLSessionDataDelegate)?) async throws -> Value {
        try await value(for: request)
    }

    func complete(_ request: Request<Void>, delegate: (any URLSessionDataDelegate)?) async throws {
        try await complete(request)
    }
}

extension JellyfinTransport: JellyfinRequestSending {
    public func response<Value: Decodable & Sendable>(for request: Request<Value>) async throws -> JellyfinResponse<Value> {
        let response = try await send(request)
        return .init(value: response.value, responseURL: response.response.url)
    }

    public func value<Value: Decodable & Sendable>(
        for request: Request<Value>,
        delegate: (any URLSessionDataDelegate)?
    ) async throws -> Value {
        try await send(request, delegate: delegate).value
    }

    public func complete(_ request: Request<Void>, delegate: (any URLSessionDataDelegate)?) async throws {
        try await send(request, delegate: delegate)
    }

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

    public func value<Value: Decodable & Sendable>(
        for request: Request<Value>,
        delegate: (any URLSessionDataDelegate)?
    ) async throws -> Value {
        try checkBinding()
        do {
            let value = try await sender.value(for: request, delegate: delegate)
            try checkBinding()
            return value
        } catch {
            try checkBinding()
            throw error
        }
    }

    public func complete(_ request: Request<Void>, delegate: (any URLSessionDataDelegate)?) async throws {
        try checkBinding()
        do {
            try await sender.complete(request, delegate: delegate)
            try checkBinding()
        } catch {
            try checkBinding()
            throw error
        }
    }

    public func response<Value: Decodable & Sendable>(for request: Request<Value>) async throws -> JellyfinResponse<Value> {
        try checkBinding()
        do {
            let response = try await sender.response(for: request)
            try checkBinding()
            return response
        } catch {
            try checkBinding()
            throw error
        }
    }
}
