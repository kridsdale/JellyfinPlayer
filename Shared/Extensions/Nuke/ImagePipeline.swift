//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Nuke
import Pulse
import SwiftfinImages
import SwiftfinNetworking

extension ImagePipeline {
    @MainActor
    enum Swiftfin {
        private static let owner = ImagePipelines(identities: ServerImageCacheIdentity.index) {
            let loader = DataLoader(configuration: TransportSessionPolicy.standard.makeConfiguration())
            loader.delegate = URLSessionProxyDelegate(logger: NetworkLogger.swiftfin(), delegate: nil)
            return loader
        }

        static var posters: ImagePipeline {
            owner.posters
        }

        static var local: ImagePipeline {
            owner.local
        }

        static var other: ImagePipeline {
            owner.other
        }
    }
}
