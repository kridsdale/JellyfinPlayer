//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation
import SwiftfinText
import Testing

struct TextContracts {
    private enum Codec: String { case h264, av1 }

    @Test
    func `conditional append is lazy and value transformations retain the source`() {
        var evaluated = false
        func suffix() -> String {
            evaluated = true
            return "!"
        }
        let original = "hello"
        #expect(original.appending(suffix(), if: false) == "hello" && !evaluated)
        #expect(original.appending(suffix(), if: true) == "hello!" && evaluated)
        #expect(original.prepending("hi ") == "hi hello")
        #expect(original.prepending("hi ", if: false) == original)
        #expect(original.removingFirst(if: false) == original)
        #expect(original.removingFirst(if: true) == "ello" && original == "hello")
        #expect(original + Character("🙂") == "hello🙂")
    }

    @Test
    func `padding counts graphemes and never truncates existing text`() {
        #expect("🙂".leftPad(maxWidth: 3, with: "0") == "00🙂")
        #expect("e\u{301}".leftPad(maxWidth: 2, with: "x") == "xe\u{301}")
        #expect("long".leftPad(maxWidth: 2, with: "0") == "long")
        #expect("".leftPad(maxWidth: -1, with: "0") == "")
    }

    @Test
    func `regular expression ranges include the entire UTF16 input`() {
        #expect("😀A😀".removeRegexMatches(pattern: "😀", replaceWith: "_") == "_A_")
        #expect("e\u{301}ABC😀".removeRegexMatches(pattern: "abc😀") == "e\u{301}")
        #expect("Hello HELLO".removeRegexMatches(pattern: "hello", replaceWith: "x") == "x x")
        #expect("stable".removeRegexMatches(pattern: "[") == "stable")
    }

    @Test
    func `legacy suffix removal retains its partial tail matching policy`() {
        #expect("abcXYZ".trimmingSuffix("badYZ") == "abcX")
        #expect("name.swift".trimmingSuffix(".swift") == "name")
        #expect("short".trimmingSuffix("longer") == "short")
        #expect("same".trimmingSuffix("same") == "")
        #expect("same".trimmingSuffix("") == "same" && "".trimmingSuffix("") == "")
    }

    @Test
    func `initials filenames blank trimming and separator trimming preserve policies`() {
        #expect("  Kevin  Ridsdale 🙂  ".initials == "KR🙂")
        #expect("/folder/My.swift.swift".shortFileName == "My")
        #expect("\n  name \t".nilIfBlank == "name")
        #expect(" \n\t".nilIfBlank == nil && "".nilIfBlank == nil)
        let text: Substring = "..value.."[...]
        #expect(text.trimmingCharacters(in: ".") == "value")
        #expect("A".multiply(by: "B") == "A × B")
    }

    @Test
    func `UTF8 encodings retain known legacy hash and base64 values`() {
        #expect("abc".sha1 == "a9993e364706816aba3e25717850c26c9cd0d89d")
        #expect("".sha1 == "da39a3ee5e6b4b0d3255bfef95601890afd80709")
        #expect("hello".base64 == "aGVsbG8=" && "".base64 == "")
        #expect("é".base64 == "w6k=")
    }

    @Test
    func `raw components retain ordering duplicates case sensitivity and omit invalid entries`() {
        let raw: String? = "h264,,invalid,av1,h264,H264"
        #expect(raw.components(of: Codec.self) == [.h264, .av1, .h264])
        #expect((nil as String?).components(of: Codec.self).isEmpty)
        #expect(("h264|av1" as String?).components(of: Codec.self, separator: "|") == [.h264, .av1])
    }

    @Test
    func `random text respects bounds alphabet and handles empty requests`() {
        let value = String.random(count: 128)
        #expect(value.count == 128 && value.allSatisfy { String.alphanumeric.contains($0) })
        let ranged = String.random(count: 4 ..< 8)
        #expect((4 ..< 8).contains(ranged.count))
        #expect(String.random(count: 0) == "" && String.random(count: -1) == "")
        #expect(String.random(count: 0 ..< 0) == "")
    }

    @Test
    func `optional and string URL parsing keeps Foundation relative query and fragment behavior`() {
        #expect(URL(string: nil as String?) == nil)
        #expect(URL(string: "http://[" as String?) == nil)
        let text = "relative/path?q=1#fragment"
        #expect(text.url == URL(string: text))
        #expect(URL(string: text as String?)?.absoluteString == text)
    }

    @Test
    func `display constants and dictation replacement characters preserve exact scalars`() throws {
        #expect(String.emptyDash == "--" && String.emptyRuntime == "--:--")
        #expect(String.empty == "" && String.space == " ")
        #expect(String.tab == "\u{0009}" && String.emDash == "—" && String.enDash == "–")
        #expect(String.hyphen == "-" && String.ellipsis == "…" && String.bullet == "•" && String.multiply == "×")
        #expect(try CharacterSet.objectReplacement.contains(#require("\u{fffc}".unicodeScalars.first)))
        #expect(try !CharacterSet.objectReplacement.contains(#require("a".unicodeScalars.first)))
    }

    @Test
    func `text operations are independent of the UI executor and application state`() async {
        let result = await Task.detached {
            (" worker ".nilIfBlank, "abc".sha1, "😀A😀".removeRegexMatches(pattern: "😀"), URL(string: nil as String?))
        }.value
        #expect(result.0 == "worker" && result.1 == "a9993e364706816aba3e25717850c26c9cd0d89d")
        #expect(result.2 == "A" && result.3 == nil)
    }
}
