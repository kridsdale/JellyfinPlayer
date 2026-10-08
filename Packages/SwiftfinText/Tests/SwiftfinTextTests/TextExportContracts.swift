//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import CoreTransferable
import Foundation
@testable import SwiftfinText
import Testing

struct TextExportContracts {
    private struct Row: Decodable { let title: String
        let body: String
        let filename: String
        let bytes: String
    }

    private struct Example: TextTransferable { let transferTitle: String
        let transferBody: String
    }

    private let original = #"""
    [
      {
        "body": "line 1\nline 2",
        "bytes": "bGluZSAxCmxpbmUgMg==",
        "filename": "title.txt",
        "title": "title"
      },
      {
        "body": "é👨‍👩‍👧‍👦\n",
        "bytes": "w6nwn5Go4oCN8J+RqeKAjfCfkafigI3wn5GmCg==",
        "filename": "你好.txt",
        "title": "你好"
      },
      {
        "body": "",
        "bytes": "",
        "filename": "record.json.txt",
        "title": "record.json"
      },
      {
        "body": "NUL\u0000終",
        "bytes": "TlVMAOe1gg==",
        "filename": ".txt",
        "title": ""
      }
    ]
    """#
    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(
            path: "kids-text-contract-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test
    func `captured titles Unicode bodies empty text and UTF8 bytes export unchanged`() throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        for row in try JSONDecoder().decode([Row].self, from: Data(original.utf8)) {
            let url = try TextExportFile.write(title: row.title, body: row.body, directory: root)
            #expect(url.deletingLastPathComponent().standardizedFileURL == root.standardizedFileURL)
            #expect(url.lastPathComponent == row.filename)
            #expect(try Data(contentsOf: url) == Data(base64Encoded: row.bytes))
        }
        _ = Example.transferRepresentation
    }

    @Test
    func `same title atomically replaces existing bytes without a stale suffix`() throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let first = try TextExportFile.write(title: "same", body: "long initial payload", directory: root)
        let second = try TextExportFile.write(title: "same", body: "x", directory: root)
        #expect(try first == second && Data(contentsOf: second) == Data("x".utf8))
    }

    @Test
    func `file export propagates write failure without returning a fabricated URL`() throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appending(path: "parent-is-file")
        try Data("occupied".utf8).write(to: file)
        do { _ = try TextExportFile.write(title: "result", body: "data", directory: file)
            Issue.record("Expected the native write failure")
        } catch { #expect((error as NSError).domain == NSCocoaErrorDomain) }
        #expect(try Data(contentsOf: file) == Data("occupied".utf8))
    }

    @Test
    func `metadata title cannot replace a file outside the export directory`() throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let exports = root.appending(path: "exports", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: exports, withIntermediateDirectories: true)
        let sibling = root.appending(path: "sentinel.txt")
        try Data("untouched".utf8).write(to: sibling)
        let url = try TextExportFile.write(title: "../sentinel", body: "export", directory: exports)
        #expect(url.deletingLastPathComponent().standardizedFileURL == exports.standardizedFileURL)
        #expect(url.lastPathComponent == ".._sentinel.txt")
        #expect(try Data(contentsOf: sibling) == Data("untouched".utf8))
        #expect(try Data(contentsOf: url) == Data("export".utf8))
    }

    @Test
    func `path separators and NUL become literal safe filename characters`() throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        for (title, filename) in [
            ("nested/title", "nested_title.txt"),
            ("/absolute", "_absolute.txt"),
            ("nul\0title", "nul_title.txt"),
            ("你好/é", "你好_é.txt"),
            ("literal%2Ftitle", "literal%2Ftitle.txt")
        ] {
            let url = try TextExportFile.write(title: title, body: "bytes", directory: root)
            #expect(url.deletingLastPathComponent().standardizedFileURL == root.standardizedFileURL)
            #expect(url.lastPathComponent == filename)
            #expect(try Data(contentsOf: url) == Data("bytes".utf8))
        }
    }
}
