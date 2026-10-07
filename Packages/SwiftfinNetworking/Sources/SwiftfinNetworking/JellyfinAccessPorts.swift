//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation
import Get
import JellyfinAPI

@MainActor
public protocol JellyfinURLResolving {
    func url(with request: Request<some Any>, queryAPIKey: Bool) -> URL?
    func url(path: String) -> URL?
}

@MainActor
public protocol JellyfinAuthenticating {
    func authenticate(username: String, password: String) async throws -> AuthenticationResult
    func authenticate(quickConnectSecret: String) async throws -> AuthenticationResult
}

extension JellyfinTransport: JellyfinURLResolving, JellyfinAuthenticating {}
