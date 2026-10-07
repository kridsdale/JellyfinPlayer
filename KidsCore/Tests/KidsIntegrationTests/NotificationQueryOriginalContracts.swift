//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Combine
import Foundation
import JellyfinAPI
import os
import SwiftfinAsyncStreams
import SwiftfinMediaCatalog
import Testing

private struct OriginalNotificationQueryFixture: Decodable {
    let originalCommit: String
    let sourceHashes: [String: String]
    let keyMemberHash: String
    let trace: [String]
    let kindValues: [String]
    let groupedItemTypes: [[String]]
}

private final class OriginalNotificationQueryTrace: Sendable {
    private let storage = OSAllocatedUnfairLock(initialState: [String]())
    func append(_ value: String) {
        storage.withLock { $0.append(value) }
    }

    var values: [String] {
        storage.withLock { $0 }
    }
}

struct NotificationQueryOriginalContracts {
    private func fixture() throws -> OriginalNotificationQueryFixture {
        let url = try #require(Bundle.module.url(forResource: "notification-query-original-f38d1814", withExtension: "json"))
        return try JSONDecoder().decode(OriginalNotificationQueryFixture.self, from: Data(contentsOf: url))
    }

    @Test
    func `original notification and grouped query source provenance`() throws {
        let original = try fixture()
        #expect(original.originalCommit == "f38d181421311bf6de7d81d853a754385229c355")
        #expect(original.sourceHashes == [
            "Shared/Services/Notifications.swift": "f3bd62db14abdc704629ecfa660b62f1b08520b5f9178e87154a00899222bd43",
            "Shared/ViewModels/ContentGroupViewModel/ItemTypeContentGroupProvider.swift": "f52cddc147c0295f2af9043769c1f331e86b388694ebfb4c2648a936c2737116"
        ])
        #expect(original.keyMemberHash == "ac62cc7aad33661c314910984b18e52f8649ea016a12b95914afb87eac25af7a")
        #expect(original.trace.count == 8 && original.groupedItemTypes.count == 37)
    }

    @Test
    func `original synchronous typed custom and void notification trace`() throws {
        let trace = OriginalNotificationQueryTrace()
        let center = NotificationCenter()
        let integers = NotificationEvent<Int>(.init("integers"))
        let raw = integers.publisher(in: center).sink { trace.append("int:\($0)") }
        trace.append("before:3")
        integers.post(3, to: center)
        trace.append("after:3")
        center.post(name: integers.name, object: nil, userInfo: ["payload": "wrong"])
        center.post(name: integers.name, object: nil, userInfo: nil)
        center.post(name: .init("other-name"), object: nil, userInfo: ["payload": 99])
        NotificationCenter().post(name: integers.name, object: nil, userInfo: ["payload": 99])
        integers.post(4, to: center)
        raw.cancel()
        integers.post(5, to: center)
        let custom = NotificationEvent<Int>(.init("custom")) { $0["number"] as? Int }
        let decoded = custom.publisher(in: center).sink { trace.append("custom:\($0)") }
        custom.post(999, to: center)
        center.post(name: custom.name, object: nil, userInfo: ["number": 7])
        center.post(name: custom.name, object: nil, userInfo: ["number": "wrong"])
        center.post(name: custom.name, object: nil, userInfo: nil)
        decoded.cancel()
        let signal = NotificationEvent<Void>(.init("signal")) { _ in trace.append("unexpected-decoder")
            return nil
        }
        let void = signal.publisher(in: center).sink { trace.append("void") }
        signal.post(to: center)
        signal.post((), to: center)
        center.post(name: signal.name, object: nil, userInfo: ["other": "anything"])
        void.cancel()
        signal.post(to: center)
        #expect(try trace.values == fixture().trace)
    }

    @Test
    func `every original grouped kind workaround preserves order and inclusion`() throws {
        let original = try fixture()
        #expect(BaseItemKind.allCases.map(\.rawValue) == original.kindValues)
        #expect(BaseItemKind.allCases.map { MediaCatalogPolicy.groupedItemTypes(for: $0).map(\.rawValue) } == original.groupedItemTypes)
    }
}
