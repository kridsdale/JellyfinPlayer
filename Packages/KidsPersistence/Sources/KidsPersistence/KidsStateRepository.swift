//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

// SPDX-License-Identifier: MPL-2.0
import CryptoKit
import Foundation
import KidsDiagnostics
import KidsDomain
import SwiftData

/// CloudKit requires defaults, no unique constraints, and no required relationships.
/// Each installation owns one row per component. The revision is inside the single
/// payload field, so CloudKit cannot merge a position with another writer's revision.
@Model
public final class KidsCloudRow {
    public var namespace: String = ""
    public var key: String = ""
    public var writerID: String = ""
    public var payload: Data = Data()

    public init(namespace: String, key: String, writerID: String, payload: Data) {
        self.namespace = namespace
        self.key = key
        self.writerID = writerID
        self.payload = payload
    }
}

public struct KidsSyncRevision: Codable, Equatable, Comparable, Sendable {
    public var milliseconds: Int64
    public var counter: Int
    public var writerID: String

    public init(milliseconds: Int64, counter: Int, writerID: String) {
        self.milliseconds = milliseconds
        self.counter = counter
        self.writerID = writerID
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        if lhs.milliseconds != rhs.milliseconds {
            return lhs.milliseconds < rhs.milliseconds
        }
        if lhs.counter != rhs.counter {
            return lhs.counter < rhs.counter
        }
        return lhs.writerID < rhs.writerID
    }
}

public enum KidsSyncValue: Codable, Equatable, Sendable {
    case ordered(KidsProgress)
    case movie(KidsProgress)
    case shuffle(KidsShuffleBag)
    case episodeLimit(Int)
    case spokenNavigation(Bool)
    case session(KidsSession)
    case deleted
    case reset(String)
    case migrated
}

public struct KidsSyncEntry: Codable, Equatable, Sendable {
    public var version = 1
    public var binding: KidsBinding
    public var key: String
    public var revision: KidsSyncRevision
    public var resetID: String?
    public var value: KidsSyncValue

    public init(binding: KidsBinding, key: String, revision: KidsSyncRevision, resetID: String?, value: KidsSyncValue) {
        self.binding = binding
        self.key = key
        self.revision = revision
        self.resetID = resetID
        self.value = value
    }
}

public struct KidsSyncSnapshot: Sendable {
    public var state: KidsState
    public var entries: [String: KidsSyncEntry]
    public var resetID: String?
    public var invalidatesPlayback = false
}

public enum KidsSyncWriteIntent: Sendable {
    case edit
    case playback
}

/// The SDK owns transport, offline queuing and the private iCloud database.
/// This small layer handles migration and application-level conflicts, including
/// independent shows, explicit resets, and duplicate records created offline.
@MainActor
public final class KidsStateRepository {
    public static let cloudContainerID = "iCloud.com.kridsdale.JellyfinPlayer"
    public let container: ModelContainer
    public let writerID: String
    private let now: () -> Date

    public init(container: ModelContainer, writerID: String, now: @escaping () -> Date = Date.init) {
        self.container = container
        self.writerID = writerID
        self.now = now
    }

    public static func makeContainer(url: URL, cloud: Bool) throws -> ModelContainer {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let schema = Schema([KidsCloudRow.self])
        let config = ModelConfiguration(
            "KidsProgress",
            schema: schema,
            url: url,
            cloudKitDatabase: cloud ? .private(cloudContainerID) : .none
        )
        return try ModelContainer(for: schema, configurations: config)
    }

    public static func namespace(for binding: KidsBinding) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return try SHA256.hash(data: encoder.encode(binding)).map { String(format: "%02x", $0) }.joined()
    }

    /// The JSON remains untouched as a rollback backup. A per-installation receipt
    /// in SwiftData prevents it being imported again after a reset or relaunch.
    public func load(binding: KidsBinding, legacyURL: URL? = nil) throws -> KidsSyncSnapshot {
        let context = ModelContext(container)
        let rows = try fetch(binding: binding, context: context)
        if !rows.contains(where: { $0.key == "migration" && $0.writerID == writerID }) {
            var entries = try decode(rows, binding: binding)
            if let legacyURL, FileManager.default.fileExists(atPath: legacyURL.path) {
                let legacy = try KidsStateFile.load(from: legacyURL, binding: binding)
                let known = Set(entries.map(\.key))
                // Migration is older than every live edit, even if cloud import arrives later.
                for (key, value) in Self.components(legacy) where !known.contains(key) {
                    let entry = KidsSyncEntry(
                        binding: binding,
                        key: key,
                        revision: .init(milliseconds: 0, counter: 0, writerID: writerID),
                        resetID: nil,
                        value: value
                    )
                    try upsert(entry, context: context, rows: rows)
                    entries.append(entry)
                }
            }
            let marker = KidsSyncEntry(
                binding: binding,
                key: "migration",
                revision: .init(milliseconds: 0, counter: 0, writerID: writerID),
                resetID: nil,
                value: .migrated
            )
            try upsert(marker, context: context, rows: rows)
            try context.save()
        }
        return try Self.resolve(decode(fetch(binding: binding, context: context), binding: binding), binding: binding)
    }

    /// Only differences from the caller's baseline are written. An unrelated
    /// remote show/movie survives even when the caller hasn't received its update.
    @discardableResult
    public func commit(
        _ desired: KidsState,
        since baseline: KidsSyncSnapshot,
        intent: KidsSyncWriteIntent = .edit,
        activeKey: String? = nil
    ) throws -> KidsSyncSnapshot {
        guard desired.binding == baseline.state.binding else { throw KidsContractError.denied }
        let context = ModelContext(container)
        let rows = try fetch(binding: desired.binding, context: context)
        let all = try decode(rows, binding: desired.binding)
        let current = try Self.resolve(all, binding: desired.binding)
        // A reset invalidates pending/offline work from the previous generation.
        guard current.resetID == baseline.resetID else {
            var result = current
            result.invalidatesPlayback = intent == .playback
            return result
        }
        let before = Self.components(baseline.state)
        let after = Self.components(desired)
        let latest = Self.components(current.state)
        var changes = Set(before.keys).union(after.keys).filter { before[$0] != after[$0] }
        var invalidatesPlayback = false
        if intent == .playback {
            var guardedKeys = Set(changes)
            if let activeKey {
                guardedKeys.insert(activeKey)
            }
            if let session = baseline.state.session, session.mode == .ordered {
                guardedKeys.insert("ordered/" + session.showID)
            }
            let moved = guardedKeys.contains { key in
                guard key.hasPrefix("ordered/"), case let .ordered(old)? = before[key],
                      case let .ordered(remote)? = latest[key]
                else {
                    return key.hasPrefix("ordered/") && latest[key] != before[key]
                }
                return old.itemID != remote.itemID || old.selectionID != remote.selectionID || old.complete != remote.complete
            }
            let movieReset = guardedKeys.contains { key in
                guard key.hasPrefix("movie/"), before[key] != nil else { return false }
                if case .movie? = latest[key] {
                    return false
                }
                return true
            }
            invalidatesPlayback = moved || movieReset
            if invalidatesPlayback {
                changes = changes.filter { !$0.hasPrefix("ordered/") && !$0.hasPrefix("movie/") &&
                    !$0.hasPrefix("shuffle/") && $0 != "session"
                }
            }
        }
        let revision = nextRevision(observing: all)
        for key in changes.sorted() {
            var value = after[key] ?? .deleted
            if case let .shuffle(local) = value, case let .shuffle(remote)? = latest[key], local.cycleID == remote.cycleID {
                var merged = local
                merged.remaining = local.remaining.filter { remote.remaining.contains($0) }
                value = .shuffle(merged)
            }
            let entry = KidsSyncEntry(
                binding: desired.binding,
                key: key,
                revision: revision,
                resetID: current.resetID,
                value: value
            )
            try upsert(entry, context: context, rows: rows)
        }
        try context.save()
        var result = try Self.resolve(
            decode(fetch(binding: desired.binding, context: context), binding: desired.binding),
            binding: desired.binding
        )
        result.invalidatesPlayback = invalidatesPlayback
        return result
    }

    /// A reset is a new generation, rather than deleting records and allowing a
    /// delayed offline device (or the legacy JSON) to resurrect old progress.
    public func reset(binding: KidsBinding) throws -> KidsSyncSnapshot {
        let context = ModelContext(container)
        let rows = try fetch(binding: binding, context: context)
        var usableRows: [KidsCloudRow] = []
        let readable = rows.compactMap { row -> KidsSyncEntry? in
            guard let entry = try? JSONDecoder().decode(KidsSyncEntry.self, from: row.payload),
                  entry.version == 1, entry.binding == binding, entry.key == row.key,
                  entry.revision.writerID == row.writerID, entry.revision.counter >= 0, entry.revision.counter < Int.max
            else {
                context.delete(row)
                return nil
            }
            usableRows.append(row)
            return entry
        }
        let entry = KidsSyncEntry(
            binding: binding,
            key: "reset",
            revision: nextRevision(observing: readable),
            resetID: nil,
            value: .reset(UUID().uuidString)
        )
        try upsert(entry, context: context, rows: usableRows)
        let marker = KidsSyncEntry(
            binding: binding,
            key: "migration",
            revision: entry.revision,
            resetID: nil,
            value: .migrated
        )
        try upsert(marker, context: context, rows: usableRows)
        try context.save()
        return try Self.resolve(readable.filter { $0.key != "reset" } + [entry], binding: binding)
    }

    public static func resolve(_ entries: [KidsSyncEntry], binding: KidsBinding) throws -> KidsSyncSnapshot {
        let scoped = entries.filter { $0.binding == binding }
        let reset = try scoped.filter { $0.key == "reset" }.max { try older($0, than: $1) }
        var resetID: String?
        if let reset {
            guard reset.version == 1, case let .reset(id) = reset.value else { throw KidsContractError.invalidStateVersion }
            resetID = id
        }
        let live = scoped.filter { $0.key != "reset" && $0.key != "migration" && $0.resetID == resetID }
        guard live.allSatisfy({ $0.version == 1 && $0.revision.counter >= 0 && $0.revision.counter < Int.max }) else {
            throw KidsContractError.invalidStateVersion
        }
        var winners: [String: KidsSyncEntry] = [:]
        for entry in live {
            if let current = winners[entry.key], try !older(current, than: entry) {
                continue
            }
            winners[entry.key] = entry
        }
        var state = KidsState(binding: binding)
        for (key, entry) in winners {
            switch entry.value {
            case let .ordered(progress):
                guard key.hasPrefix("ordered/"), valid(progress) else { throw KidsContractError.invalidStateVersion }
                state.ordered[String(key.dropFirst(8))] = progress
            case let .movie(progress):
                guard key.hasPrefix("movie/"), valid(progress) else { throw KidsContractError.invalidStateVersion }
                state.movies[String(key.dropFirst(6))] = progress
            case var .shuffle(bag):
                guard key.hasPrefix("shuffle/"), Set(bag.remaining).count == bag.remaining.count else {
                    throw KidsContractError.invalidStateVersion
                }
                // Independent draws in the same cycle combine by intersection:
                // an episode consumed by either TV remains consumed on both.
                for candidate in live where candidate.key == key {
                    if case let .shuffle(other) = candidate.value, other.cycleID == bag.cycleID {
                        bag.remaining = bag.remaining.filter { other.remaining.contains($0) }
                    }
                }
                state.shuffle[String(key.dropFirst(8))] = bag
            case let .episodeLimit(limit):
                guard key == "limit", [0, 1, 2].contains(limit) else { throw KidsContractError.invalidStateVersion }
                state.preferences.episodeLimit = limit
            case let .spokenNavigation(spoken):
                guard key == "spoken" else { throw KidsContractError.invalidStateVersion }
                state.preferences.spokenNavigation = spoken
            case let .session(session):
                guard key == "session", session.seconds.isFinite, session.seconds >= 0,
                      session.completed >= 0, [0, 1, 2].contains(session.limit) else { throw KidsContractError.invalidStateVersion }
                state.session = session
            case .deleted: break
            default: throw KidsContractError.invalidStateVersion
            }
        }
        return KidsSyncSnapshot(state: state, entries: winners, resetID: resetID)
    }

    private static func older(_ lhs: KidsSyncEntry, than rhs: KidsSyncEntry) throws -> Bool {
        if lhs.revision != rhs.revision {
            return lhs.revision < rhs.revision
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return try encoder.encode(lhs).lexicographicallyPrecedes(encoder.encode(rhs))
    }

    private static func valid(_ progress: KidsProgress) -> Bool {
        progress.seconds.isFinite && progress.seconds >= 0
    }

    private static func components(_ state: KidsState) -> [String: KidsSyncValue] {
        var result: [String: KidsSyncValue] = [
            "limit": .episodeLimit(state.preferences.episodeLimit),
            "spoken": .spokenNavigation(state.preferences.spokenNavigation)
        ]
        for (id, progress) in state.ordered {
            result["ordered/" + id] = .ordered(progress)
        }
        for (id, progress) in state.movies {
            result["movie/" + id] = .movie(progress)
        }
        for (id, bag) in state.shuffle {
            result["shuffle/" + id] = .shuffle(bag)
        }
        if let session = state.session {
            result["session"] = .session(session)
        }
        return result
    }

    private func nextRevision(observing entries: [KidsSyncEntry]) -> KidsSyncRevision {
        let latest = entries.map(\.revision).max()
        let clock = Int64(now().timeIntervalSince1970 * 1000)
        let milliseconds = max(clock, latest?.milliseconds ?? 0)
        let counter = latest?.milliseconds == milliseconds ? latest!.counter + 1 : 0
        return .init(milliseconds: milliseconds, counter: counter, writerID: writerID)
    }

    private func fetch(binding: KidsBinding, context: ModelContext) throws -> [KidsCloudRow] {
        let namespace = try Self.namespace(for: binding)
        return try context.fetch(FetchDescriptor<KidsCloudRow>(predicate: #Predicate { $0.namespace == namespace }))
    }

    private func decode(_ rows: [KidsCloudRow], binding: KidsBinding) throws -> [KidsSyncEntry] {
        try rows.map { row in
            let entry: KidsSyncEntry
            do { entry = try JSONDecoder().decode(KidsSyncEntry.self, from: row.payload) }
            catch { throw KidsContractError.invalidStateVersion }
            guard entry.binding == binding, entry.key == row.key, entry.revision.writerID == row.writerID, entry.revision.counter >= 0,
                  entry.revision.counter < Int.max
            else {
                throw KidsContractError.invalidStateVersion
            }
            return entry
        }
    }

    private func upsert(_ entry: KidsSyncEntry, context: ModelContext, rows: [KidsCloudRow]) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let data = try encoder.encode(entry)
        let owned = rows.filter { $0.key == entry.key && $0.writerID == writerID }
        if owned.isEmpty {
            try context.insert(KidsCloudRow(
                namespace: Self.namespace(for: entry.binding),
                key: entry.key,
                writerID: writerID,
                payload: data
            ))
        } else {
            for row in owned {
                row.payload = data
            }
        }
    }
}
