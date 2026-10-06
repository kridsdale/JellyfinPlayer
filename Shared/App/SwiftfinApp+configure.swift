//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import FactoryKit
import Logging
import Nuke
import PulseLogHandler
import SwiftfinCollections
import SwiftfinStorage
import UIKit

extension SwiftfinApp {

    static func configure() {

        // Logging
        LoggingSystem.bootstrap { label in

            // TODO: have setting for log level
            //       - default info, boolean to go down to trace
            let handlers: [any LogHandler] = [PersistentLogHandler(label: label)]
                #if DEBUG
                    .appending(SwiftfinConsoleHandler())
                #endif

            var multiplexHandler = MultiplexLogHandler(handlers)
            multiplexHandler.logLevel = .trace
            return multiplexHandler
        }

        // CoreStore

        let storageLogger = Logger.swiftfin()
        StorageLogging.bootstrap { entry in
            let level: Logger.Level = switch entry.level {
            case .trace: .trace
            case .debug: .debug
            case .warning: .warning
            case .critical: .critical
            }
            storageLogger.log(
                level: level,
                "\(entry.message)",
                source: "Corestore",
                file: entry.file,
                function: entry.function,
                line: entry.line
            )
        }

        // Nuke
        #if os(tvOS)
        ServerImageCacheIdentity.start()
        #endif

        ImageCache.shared.costLimit = 1024 * 1024 * 200 // 200 MB
        ImageCache.shared.ttl = 300 // 5 min

        ImageDecoderRegistry.shared.register { context in
            guard let mimeType = context.urlResponse?.mimeType else { return nil }
            return mimeType.contains("svg") ? ImageDecoders.Empty() : nil
        }

        ImagePipeline.shared = .Swiftfin.posters
    }
}
