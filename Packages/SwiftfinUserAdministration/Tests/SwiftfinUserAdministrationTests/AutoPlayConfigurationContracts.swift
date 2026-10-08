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
import SwiftfinNetworking
import SwiftfinUserAdministration
import Testing

private enum ConfigurationFailure: Error { case offline, retired }
@MainActor
private final class ConfigurationBinding { var current = true
    var caller = true
}

@MainActor
private final class ConfigurationSender: JellyfinRequestSending {
    struct Call { let path: String
        let method: String
        let userID: String?
        let body: UserConfiguration
    }

    var calls: [Call] = []
    var firstPending: CheckedContinuation<Void, Never>?
    var holdFirst = false
    var failFirst = false
    func value<Value: Decodable & Sendable>(for _: Request<Value>) async throws -> Value {
        throw ConfigurationFailure.offline
    }

    func complete(_ request: Request<Void>) async throws {
        let data = try #require(request.body.map { try JSONEncoder().encode($0) })
        try calls.append(.init(
            path: request.url?.path ?? "",
            method: request.method.rawValue,
            userID: request.query?.first { $0.0 == "userId" }?.1,
            body: JSONDecoder().decode(UserConfiguration.self, from: data)
        ))
        let first = calls.count == 1
        if first, holdFirst {
            await withCheckedContinuation { firstPending = $0 }
        }
        if first, failFirst {
            throw ConfigurationFailure.offline
        }
    }

    func release() {
        firstPending?.resume()
        firstPending = nil
    }
}

@MainActor
private func settleConfiguration(_ ready: () -> Bool) async {
    for _ in 0 ..< 2000 {
        if ready() {
            return
        }
        await Task.yield()
    }
    #expect(ready())
}

@Suite("Bound Auto Play configuration")
@MainActor
struct AutoPlayConfigurationContracts {
    private func writer(_ sender: ConfigurationSender, _ binding: ConfigurationBinding = .init()) -> UserConfigurationUpdates {
        UserAdministrationClient(executor: .init(sender: sender, isCurrent: { binding.current }), currentUserID: "captured-user")
            .configurationUpdates()
    }

    @Test
    func `current account and untouched sibling configuration are captured before IO`() async throws {
        let sender = ConfigurationSender(), updates = writer(sender)
        let original = UserConfiguration(myMediaExcludes: ["approved-library"])
        var admitted: UserConfiguration?
        #expect(try updates.toggle(from: original, willSubmit: { admitted = $0 }))
        #expect(sender.calls.isEmpty && admitted?.enableNextEpisodeAutoPlay == true)
        await updates.waitUntilFinished()
        let call = try #require(sender.calls.first)
        #expect(call.path == "/Users/Configuration" && call.method == "POST" && call.userID == "captured-user")
        #expect(call.body.enableNextEpisodeAutoPlay == true && call.body.myMediaExcludes == ["approved-library"])
        #expect(original.enableNextEpisodeAutoPlay == nil)
    }

    @Test
    func `rapid queued toggles retain only the latest submitted snapshot`() async throws {
        let sender = ConfigurationSender(), updates = writer(sender)
        try updates.toggle(from: .init(enableNextEpisodeAutoPlay: false))
        try updates.toggle(from: .init(enableNextEpisodeAutoPlay: true, myMediaExcludes: ["latest"]))
        await updates.waitUntilFinished()
        #expect(sender.calls.count == 1 && sender.calls.first?.body.enableNextEpisodeAutoPlay == false)
        #expect(sender.calls.first?.body.myMediaExcludes == ["latest"])
    }

    @Test
    func `accepted write drains before latest update and intermediate queued write is coalesced`() async throws {
        let sender = ConfigurationSender()
        sender.holdFirst = true
        let updates = writer(sender)
        try updates.toggle(from: .init(enableNextEpisodeAutoPlay: false, myMediaExcludes: ["first"]))
        await settleConfiguration { sender.firstPending != nil }
        try updates.toggle(from: .init(enableNextEpisodeAutoPlay: true, myMediaExcludes: ["intermediate"]))
        try updates.toggle(from: .init(enableNextEpisodeAutoPlay: false, myMediaExcludes: ["latest"]))
        for _ in 0 ..< 20 {
            await Task.yield()
        }
        #expect(sender.calls.count == 1)
        sender.release()
        await updates.waitUntilFinished()
        #expect(sender.calls.count == 2 && sender.calls.map(\.body.myMediaExcludes) == [["first"], ["latest"]])
    }

    @Test
    func `binding replacement retires pending response and every queued or new admission`() async throws {
        let sender = ConfigurationSender()
        sender.holdFirst = true
        sender.failFirst = true
        let binding = ConfigurationBinding(), updates = writer(sender, binding)
        var failures = 0, admissions = 0
        try updates.toggle(from: .init(), willSubmit: { _ in admissions += 1 }, failure: { _ in failures += 1 })
        await settleConfiguration { sender.firstPending != nil }
        try updates.toggle(from: .init(enableNextEpisodeAutoPlay: true), failure: { _ in failures += 1 })
        binding.current = false
        sender.release()
        await updates.waitUntilFinished()
        #expect(sender.calls.count == 1 && failures == 0)
        #expect(throws: CancellationError.self) { try updates.toggle(from: .init(), willSubmit: { _ in admissions += 1 }) }
        #expect(admissions == 1)
    }

    @Test
    func `current failure is reported once and later intent can retry without rollback`() async throws {
        let sender = ConfigurationSender()
        sender.failFirst = true
        let updates = writer(sender)
        var optimistic: UserConfiguration?, failures = 0
        try updates.toggle(from: .init(), willSubmit: { optimistic = $0 }, failure: { _ in failures += 1 })
        await updates.waitUntilFinished()
        #expect(failures == 1 && optimistic?.enableNextEpisodeAutoPlay == true)
        try updates.toggle(from: .init(enableNextEpisodeAutoPlay: true), failure: { _ in failures += 1 })
        await updates.waitUntilFinished()
        #expect(sender.calls.count == 2 && failures == 1 && sender.calls.last?.body.enableNextEpisodeAutoPlay == false)
    }

    @Test
    func `synchronous admission reentry can cancel or replace before any command`() async throws {
        let sender = ConfigurationSender(), updates = writer(sender)
        #expect(throws: CancellationError.self) {
            try updates.toggle(from: .init(), willSubmit: { _ in updates.cancel() })
        }
        #expect(sender.calls.isEmpty)
        #expect(throws: CancellationError.self) {
            try updates.toggle(from: .init(), willSubmit: { _ in
                _ = try? updates.toggle(from: .init(enableNextEpisodeAutoPlay: true))
            })
        }
        await updates.waitUntilFinished()
        #expect(sender.calls.count == 1 && sender.calls.first?.body.enableNextEpisodeAutoPlay == false)
    }

    @Test
    func `retired caller checkpoint and explicit cancel suppress failures and queued IO`() async throws {
        let sender = ConfigurationSender(), binding = ConfigurationBinding(), updates = writer(sender, binding)
        var failures = 0
        try updates.toggle(
            from: .init(),
            validate: {
                if !binding.caller {
                    throw ConfigurationFailure.retired
                }
            },
            failure: { _ in failures += 1 }
        )
        binding.caller = false
        await updates.waitUntilFinished()
        #expect(sender.calls.isEmpty && failures == 0)
        try updates.toggle(from: .init(), failure: { _ in failures += 1 })
        updates.cancel()
        await updates.waitUntilFinished()
        #expect(sender.calls.isEmpty && failures == 0)
    }

    @Test
    func `cancelled submission preserves an accepted predecessor and cancellation cannot overtake it`() async throws {
        let sender = ConfigurationSender()
        sender.holdFirst = true
        let updates = writer(sender)
        try updates.toggle(from: .init())
        await settleConfiguration { sender.firstPending != nil }
        let cancelled = Task { () throws in
            withUnsafeCurrentTask { $0?.cancel() }
            try updates.toggle(from: .init(enableNextEpisodeAutoPlay: true))
        }
        await #expect(throws: CancellationError.self) { try await cancelled.value }
        updates.cancel()
        try updates.toggle(from: .init(enableNextEpisodeAutoPlay: true, myMediaExcludes: ["after-cancel"]))
        for _ in 0 ..< 20 {
            await Task.yield()
        }
        #expect(sender.calls.count == 1)
        sender.release()
        await updates.waitUntilFinished()
        #expect(sender.calls.count == 2 && sender.calls.last?.body.myMediaExcludes == ["after-cancel"])
    }

    @Test
    func `replacement transport writer waits for the retired accepted predecessor`() async throws {
        let oldSender = ConfigurationSender()
        oldSender.holdFirst = true
        let oldBinding = ConfigurationBinding(), old = writer(oldSender, oldBinding)
        try old.toggle(from: .init())
        await settleConfiguration { oldSender.firstPending != nil }
        oldBinding.current = false
        old.cancel()
        let newSender = ConfigurationSender()
        let client = UserAdministrationClient(executor: .init(sender: newSender), currentUserID: "replacement-user")
        let replacement = client.configurationUpdates(after: old)
        try replacement.toggle(from: .init(enableNextEpisodeAutoPlay: true))
        for _ in 0 ..< 20 {
            await Task.yield()
        }
        #expect(newSender.calls.isEmpty)
        oldSender.release()
        await replacement.waitUntilFinished()
        #expect(oldSender.calls.count == 1 && newSender.calls.count == 1)
        #expect(newSender.calls.first?.userID == "replacement-user" && newSender.calls.first?.body.enableNextEpisodeAutoPlay == false)
    }
}
