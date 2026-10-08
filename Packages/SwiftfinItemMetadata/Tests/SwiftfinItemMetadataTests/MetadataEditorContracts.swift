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
import SwiftfinItemMetadata
import SwiftfinNetworking
import Testing

private enum EditorFailure: Error { case offline }
@MainActor
private final class EditorBinding {
    var current = true
    var caller = true
    func validate() throws {
        if !caller {
            throw CancellationError()
        }
    }
}

@MainActor
private final class EditorSender: JellyfinRequestSending {
    struct Call { let path: String
        let method: String
        let query: [String: String]
        let body: Data?
    }

    var calls: [Call] = []
    var profile = BaseItemDto(id: "item", name: "Fresh")
    var images: [ImageInfo] = [.init(imageIndex: 0, imageType: .primary)]
    var failingPath: String?
    var holdMutation = false
    var holdRead = false
    var mutationHeld = false
    var readHeld = false
    var pending: CheckedContinuation<Void, Never>?
    private func record(_ request: Request<some Any>) throws {
        try calls.append(.init(
            path: request.url?.path ?? "",
            method: request.method.rawValue,
            query: Dictionary(uniqueKeysWithValues: (request.query ?? []).compactMap { k, v in v.map { (k, $0) } }),
            body: request.body.map { try JSONEncoder().encode($0) }
        ))
    }

    func complete(_ request: Request<Void>) async throws {
        try record(request)
        if holdMutation && !mutationHeld {
            mutationHeld = true
            await withCheckedContinuation { pending = $0 }
        }
        if request.url?.path == failingPath {
            throw EditorFailure.offline
        }
    }

    func value<Value: Decodable & Sendable>(for request: Request<Value>) async throws -> Value {
        try record(request)
        if holdRead && !readHeld {
            readHeld = true
            await withCheckedContinuation { pending = $0 }
        }
        if request.url?.path == failingPath {
            throw EditorFailure.offline
        }
        let data: Data = if request.url?.path.hasSuffix("/Images") == true {
            try JSONEncoder().encode(images)
        } else if String(describing: Value.self).hasPrefix("Array<") {
            Data("[]".utf8)
        } else {
            try JSONEncoder().encode(profile)
        }
        return try JSONDecoder().decode(Value.self, from: data)
    }

    func release() {
        pending?.resume()
        pending = nil
    }
}

@MainActor
private func settleEditor(_ condition: () -> Bool) async {
    for _ in 0 ..< 2000 {
        if condition() {
            return
        }
        await Task.yield()
    }
    #expect(condition())
}

@Suite("Bound metadata edit sequences") @MainActor
struct MetadataEditorContracts {
    private func client(_ sender: EditorSender, _ binding: EditorBinding = .init()) -> ItemMetadataClient {
        .init(
            executor: .init(sender: sender, isCurrent: { binding.current }),
            userID: "captured-user",
            bindingID: .init(transport: ObjectIdentifier(sender), userID: "captured-user")
        )
    }

    private var options: MetadataRefreshOptions {
        .init(
            metadataMode: .fullRefresh,
            imageMode: .fullRefresh,
            replaceMetadata: false,
            replaceImages: false,
            regenerateTrickplay: false
        )
    }

    @Test
    func `missing and retired editor targets are rejected without IO`() throws {
        let sender = EditorSender(), binding = EditorBinding(), client = client(sender, binding)
        #expect(throws: ItemMetadataEditor.BindingError.self) { try client.makeEditor(itemID: "") }
        binding.current = false
        #expect(throws: CancellationError.self) { try client.makeEditor(itemID: "item") }
        #expect(sender.calls.isEmpty)
    }

    @Test
    func `update and reload retain the original item and authenticated user`() async throws {
        let sender = EditorSender(), editor = try client(sender).makeEditor(itemID: "item")
        let updated = try await editor.update(.init(id: "item", name: "Submitted"))
        #expect(updated.id == "item" && updated.name == "Fresh")
        #expect(sender.calls.map(\.path) == ["/Items/item", "/Items/item"])
        #expect(sender.calls.map(\.method) == ["POST", "GET"] && sender.calls.last?.query["userId"] == "captured-user")
        await #expect(throws: CancellationError.self) { try await editor.update(.init(id: "different")) }
        #expect(sender.calls.count == 2)
    }

    @Test
    func `cancelled accepted edit drains before its successor without stale reload`() async throws {
        let sender = EditorSender()
        sender.holdMutation = true
        let editor = try client(sender).makeEditor(itemID: "item")
        let first = Task { try await editor.update(.init(id: "item", name: "Old")) }
        await settleEditor { sender.pending != nil }
        first.cancel()
        let second = Task { try await editor.update(.init(id: "item", name: "New")) }
        for _ in 0 ..< 30 {
            await Task.yield()
        }
        #expect(sender.calls.count == 1)
        sender.release()
        do { _ = try await first.value
            Issue.record("Cancelled edit returned a receipt")
        } catch is CancellationError {} catch {
            Issue.record("Unexpected failure: \(error)")
        }
        _ = try await second.value
        #expect(sender.calls.map(\.method) == ["POST", "POST", "GET"])
        let payload = try JSONDecoder().decode(BaseItemDto.self, from: #require(sender.calls[1].body))
        #expect(payload.name == "New")
    }

    @Test
    func `refresh start reentry retires wait and reload`() async throws {
        let sender = EditorSender(), binding = EditorBinding(), editor = try client(sender, binding).makeEditor(itemID: "item")
        var starts = 0, waits = 0
        await #expect(throws: CancellationError.self) {
            try await editor.refresh(
                options: options,
                validate: binding.validate,
                started: { starts += 1
                    binding.caller = false
                },
                wait: { _ in waits += 1 }
            )
        }
        #expect(starts == 1 && waits == 0 && sender.calls.count == 1)
    }

    @Test
    func `refresh keeps the inherited delay and rechecks account after waiting`() async throws {
        let sender = EditorSender(), binding = EditorBinding(), editor = try client(sender, binding).makeEditor(itemID: "item")
        var delay: Duration?
        await #expect(throws: CancellationError.self) {
            try await editor.refresh(options: options, wait: { delay = $0
                binding.current = false
            })
        }
        #expect(delay == .seconds(5) && sender.calls.count == 1)
    }

    @Test
    func `image delete preserves partial item receipt when image reload fails`() async throws {
        let sender = EditorSender()
        sender.failingPath = "/Items/item/Images"
        let editor = try client(sender).makeEditor(itemID: "item")
        var partial: BaseItemDto?
        await #expect(throws: EditorFailure.self) {
            try await editor.editImage(.delete(.init(imageType: .primary)), reloadedItem: { value in
                #expect(sender.calls.count == 2)
                partial = value
            })
        }
        #expect(partial?.id == "item")
        #expect(sender.calls.map(\.path) == ["/Items/item/Images/Primary", "/Items/item", "/Items/item/Images"])
    }

    @Test
    func `image publication reentry prevents subsequent image read`() async throws {
        let sender = EditorSender(), binding = EditorBinding(), editor = try client(sender, binding).makeEditor(itemID: "item")
        await #expect(throws: CancellationError.self) {
            try await editor.editImage(
                .delete(.init(imageType: .primary)),
                validate: binding.validate,
                reloadedItem: { _ in binding.caller = false }
            )
        }
        #expect(sender.calls.count == 2)
    }

    @Test
    func `image no op and successful upload retain exact reload and payload semantics`() async throws {
        let sender = EditorSender(), editor = try client(sender).makeEditor(itemID: "item")
        #expect(try await editor.editImage(.remote(.init())) == nil)
        #expect(try await editor.editImage(.delete(.init())) == nil)
        #expect(sender.calls.isEmpty)
        let images = try await editor.editImage(.upload(type: .primary, data: Data([0, 255]), contentType: "image/png"))
        #expect(images?[.primary]?.count == 1)
        #expect(sender.calls.map(\.path) == ["/Items/item/Images/Primary", "/Items/item/Images"])
    }

    @Test
    func `subtitle upload captures language bytes and flags then returns the selected item`() async throws {
        let sender = EditorSender(), editor = try client(sender).makeEditor(itemID: "item")
        let updated = try await editor.editSubtitles(.upload(
            data: Data([0, 255]),
            format: "srt",
            language: "eng",
            forced: true,
            hearingImpaired: false
        ))
        let body = try #require(sender.calls.first?.body)
        let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(json["Language"] as? String == "eng" && json["Data"] as? String == Data([0, 255]).base64EncodedString())
        #expect(json["IsForced"] as? Bool == true && json["IsHearingImpaired"] as? Bool == false)
        #expect(updated.id == "item" && sender.calls.count == 2 && sender.calls.last?.method == "GET")
    }

    @Test
    func `subtitle query uses emitted snapshot and retired network error is cancellation`() async throws {
        let sender = EditorSender(), binding = EditorBinding(), editor = try client(sender, binding).makeEditor(itemID: "item")
        #expect(try await editor.searchSubtitles(.init(language: nil, perfectMatch: false)).isEmpty && sender.calls.isEmpty)
        sender.holdRead = true
        let submitted = MetadataSubtitleQuery(language: "eng", perfectMatch: true)
        let task = Task { try await editor.searchSubtitles(submitted, validate: binding.validate) }
        await settleEditor { sender.pending != nil }
        #expect(sender.calls.first?.query["isPerfectMatch"] == "true" && sender.calls.first?.path.contains("eng") == true)
        sender.failingPath = sender.calls.first?.path
        binding.caller = false
        sender.release()
        do { _ = try await task.value
            Issue.record("Retired search returned")
        } catch is CancellationError {} catch { Issue.record("Obsolete failure leaked: \(error)") }
    }

    @Test
    func `subtitle deletion preserves descending indices and stops at indexed failure`() async throws {
        let sender = EditorSender(), editor = try client(sender).makeEditor(itemID: "item")
        sender.failingPath = "/Videos/item/Subtitles/2"
        do { _ = try await editor.editSubtitles(.delete([1, 7, 2]))
            Issue.record("Expected deletion failure")
        } catch let failure as MetadataSubtitleDeletionFailure { #expect(failure.index == 2 && failure.underlying is EditorFailure) }
        #expect(sender.calls.map(\.path) == ["/Videos/item/Subtitles/7", "/Videos/item/Subtitles/2"])
    }

    @Test
    func `wrong reloaded identity rejects item receipt`() async throws {
        let sender = EditorSender()
        sender.profile.id = "different"
        let editor = try client(sender).makeEditor(itemID: "item")
        await #expect(throws: CancellationError.self) { try await editor.item() }
        #expect(sender.calls.count == 1)
    }
}
