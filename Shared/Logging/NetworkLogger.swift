//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation
import Pulse
import SwiftfinNetworking

private let redactedMessage = "<Redacted by Swiftfin>"

extension NetworkLogger {

    static func swiftfin() -> NetworkLogger {
        var configuration = NetworkLogger.Configuration()

        #if os(tvOS)
        configuration.willHandleEvent = { _ in nil }
        #else
        configuration.willHandleEvent = { event -> LoggerStore.Event? in
            if case var LoggerStore.Event.networkTaskCompleted(task) = event {
                guard let url = task.originalRequest.url,
                      let requestBody = task.requestBody
                else {
                    return event
                }

                task.requestBody = JellyfinRequestBodyRedactor.body(at: url, body: requestBody, replacement: redactedMessage)
                return LoggerStore.Event.networkTaskCompleted(task)
            }

            return event
        }

        #endif
        return NetworkLogger(configuration: configuration)
    }
}
