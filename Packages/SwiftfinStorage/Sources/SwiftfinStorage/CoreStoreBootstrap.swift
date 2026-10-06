//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

// SDK 9.2's unannotated global cannot express a startup-only write in Swift 6.
// This private interoperability file contains exactly that write. Its caller
// prevents installation after database construction and repeated replacement.
// Native schemas, storage operations and logger values use normal checked imports.
@preconcurrency import CoreStore

@MainActor
func installLegacyCoreStoreLogger(_ logger: NativeStorageLogger) {
    CoreStoreDefaults.logger = logger
}
