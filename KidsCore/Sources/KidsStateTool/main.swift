//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

// SPDX-License-Identifier: MPL-2.0
// Internal simulator tooling: never contacts Jellyfin, CloudKit, or media volumes.
import Foundation
import KidsCore
import KidsPersistence
import SwiftData

@main
struct KidsStateTool {
    @MainActor
    static func main() throws {
        let args = CommandLine.arguments
        guard args.count == 5, ["export", "import"].contains(args[1]) else {
            throw NSError(domain: "KidsStateTool usage: export|import STORE BINDING_JSON STATE_JSON", code: 1)
        }
        let storeURL = URL(fileURLWithPath: args[2]).resolvingSymlinksInPath()
        let root = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Developer/CoreSimulator/Devices/")
        guard storeURL.path.hasPrefix(root.path + "/"), storeURL.lastPathComponent == "progress.store",
              FileManager.default.fileExists(atPath: storeURL.path) else { throw KidsContractError.denied }
        let binding = try JSONDecoder().decode(KidsBinding.self, from: Data(contentsOf: URL(fileURLWithPath: args[3])))
        let container = try KidsStateRepository.makeContainer(url: storeURL, cloud: false)
        let context = ModelContext(container)
        let namespace = try KidsStateRepository.namespace(for: binding)
        let rows = try context.fetch(FetchDescriptor<KidsCloudRow>(predicate: #Predicate { $0.namespace == namespace }))
        let entries = try rows.map { try JSONDecoder().decode(KidsSyncEntry.self, from: $0.payload) }
        let snapshot = try KidsStateRepository.resolve(entries, binding: binding)
        let stateURL = URL(fileURLWithPath: args[4])
        if args[1] == "export" {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .sortedKeys
            try encoder.encode(snapshot.state).write(to: stateURL, options: .atomic)
        } else {
            let desired = try JSONDecoder().decode(KidsState.self, from: Data(contentsOf: stateURL))
            guard desired.version == 1, desired.binding == binding else { throw KidsContractError.denied }
            let repository = KidsStateRepository(container: container, writerID: "simulator-validation")
            _ = try repository.commit(desired, since: snapshot)
        }
    }
}
