//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

// SPDX-License-Identifier: MPL-2.0
import Foundation
import KidsDomain

public enum KidsStateFile {
    public static func load(from url: URL, binding: KidsBinding) throws -> KidsState {
        guard FileManager.default.fileExists(atPath: url.path) else { return KidsState(binding: binding) }
        let data = try Data(contentsOf: url)
        let state: KidsState
        do {
            state = try JSONDecoder().decode(KidsState.self, from: data)
        } catch is DecodingError {
            throw KidsContractError.invalidStateVersion
        }
        guard state.version == 1 else { throw KidsContractError.invalidStateVersion }
        return state.binding == binding ? state : KidsState(binding: binding)
    }

    public static func save(_ state: KidsState, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(state).write(to: url, options: .atomic)
    }
}
