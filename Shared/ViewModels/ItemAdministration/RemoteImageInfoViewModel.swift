//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Combine
import JellyfinAPI

@MainActor
final class RemoteImageInfoViewModel: ObservableObject {

    var remoteImageLibrary: PagingLibraryViewModel<RemoteImageLibrary>
    let remoteImageProvidersLibrary: PagingLibraryViewModel<RemoteImageProvidersLibrary>

    private let validate: @MainActor @Sendable () throws -> Void

    init(itemID: String, imageType: ImageType, validate: @escaping @MainActor @Sendable () throws -> Void = {}) {
        self.validate = validate
        self.remoteImageLibrary = .init(
            library: .init(
                imageType: imageType,
                itemID: itemID
            ),
            validate: validate
        )
        self.remoteImageProvidersLibrary = .init(
            library: .init(itemID: itemID),
            validate: validate
        )
    }

    func refresh() {
        guard (try? validate()) != nil else { return }
        remoteImageLibrary.refresh()
        remoteImageProvidersLibrary.refresh()
    }
}
