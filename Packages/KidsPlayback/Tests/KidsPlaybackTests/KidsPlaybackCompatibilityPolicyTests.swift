//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

// SPDX-License-Identifier: MPL-2.0
@testable import KidsPlayback
import Testing

struct KidsPlaybackCompatibilityPolicyTests {
    @Test
    func `exact observed combination requests compatible stream`() {
        #expect(KidsPlaybackCompatibilityPolicy.requiresCompatibleStream(videoCodec: "mpeg4", container: "avi"))
    }

    @Test
    func `case and surrounding whitespace are normalized`() {
        for (codec, container) in [
            ("MPEG4", "AVI"),
            ("MpEg4", "aVi"),
            (" \nMPEG4\t", "\r AVI \n"),
            ("\u{00A0}mpeg4\u{00A0}", "\tavi\t")
        ] {
            #expect(KidsPlaybackCompatibilityPolicy.requiresCompatibleStream(videoCodec: codec, container: container))
        }
    }

    @Test
    func `absent or empty metadata does not guess compatibility`() {
        let metadata: [(String?, String?)] = [
            (nil, nil), (nil, "avi"), ("mpeg4", nil),
            ("", "avi"), ("mpeg4", ""), (" \n\t", "avi"), ("mpeg4", " \n\t")
        ]
        for (codec, container) in metadata {
            #expect(!KidsPlaybackCompatibilityPolicy.requiresCompatibleStream(videoCodec: codec, container: container))
        }
    }

    @Test
    func `other codecs in AVI keep their existing policy`() {
        for codec in ["h264", "hevc", "av1", "mpeg1video", "mpeg2video", "msmpeg4v2", "msmpeg4v3", "xvid", "divx", "mp4v"] {
            #expect(!KidsPlaybackCompatibilityPolicy.requiresCompatibleStream(videoCodec: codec, container: "avi"))
        }
    }

    @Test
    func `MPEG 4 in other containers keeps its existing policy`() {
        for container in ["mp4", "m4v", "mov", "mkv", "matroska", "webm", "wmv", "asf", "mpeg", "ts"] {
            #expect(!KidsPlaybackCompatibilityPolicy.requiresCompatibleStream(videoCodec: "mpeg4", container: container))
        }
    }

    @Test
    func `composite aliases and embedded characters are not coerced`() {
        for codec in ["mpeg4,h264", "mpeg4/h264", "mpeg4 (xvid)", "video/mpeg4", "mpeg-4", "mpeg 4", "mpeg4\0", "ｍpeg4"] {
            #expect(!KidsPlaybackCompatibilityPolicy.requiresCompatibleStream(videoCodec: codec, container: "avi"))
        }
        for container in ["avi,mov", "avi/mkv", "avi (video)", "video/avi", ".avi", "file.avi", "a vi", "avi\0", "ａvi"] {
            #expect(!KidsPlaybackCompatibilityPolicy.requiresCompatibleStream(videoCodec: "mpeg4", container: container))
        }
    }
}
