//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

// SPDX-License-Identifier: MPL-2.0
import Foundation
import KidsDiagnostics
import Testing

@Test
func `native probe and terminal decoder failures have distinct fixed codes`() {
    #expect(KidsNativeDiagnostic(message: "'DIVX' is not supported") == .hardwareProbeRejected)
    #expect(KidsNativeDiagnostic(message: "Codec 'DIVX' (fixture) is not supported.") == .decoderUnavailable)
    #expect(KidsNativeDiagnostic(message: "provided view container is nil") == .missingDrawable)
    #expect(KidsNativeDiagnostic(message: "Creating UIView window provider failed") == .windowProviderRejected)
    #expect(KidsNativeDiagnostic(message: "Failed to create video converter") == .converterRejected)
    #expect(KidsNativeDiagnostic(message: "buffer deadlock prevented") == .bufferDeadlockPrevented)
}

@Test
func `native diagnostics never serialize a raw message or connection details`() throws {
    let secret = "private-token-never-record"
    let reason = KidsNativeDiagnostic(message: "Unable to read http://private.invalid/video?token=" + secret)
    #expect(reason == .other)
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let recorder = KidsPerformanceRecorder(enabled: true, directory: directory)
    let span = try #require(recorder.begin(.playback))
    span.mark(.nativeDiagnostic, values: [
        "native_reason": Double(reason.rawValue),
        "native_severity": 4,
        "native_module": Double(KidsNativeModule(secret).rawValue),
        "native_context": Double(KidsNativeContext(message: secret).rawValue)
    ])
    span.finish()
    recorder.flush()
    let file = try #require(FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).first)
    let text = try String(contentsOf: file, encoding: .utf8)
    #expect(text.contains("nativeDiagnostic"))
    #expect(text.contains("native_reason"))
    #expect(!text.contains(secret))
    #expect(!text.contains("private.invalid"))
}

@Test
func `native diagnostic context has only fixed module codes and feature bits`() {
    #expect(KidsNativeModule("avcodec") == .avcodec)
    #expect(KidsNativeModule("VideoToolbox") == .videotoolbox)
    #expect(KidsNativeModule("http://private.invalid?token=secret") == .other)
    let flags = KidsNativeContext(message: "hardware decoder rejected pixel format allocation")
    #expect(flags == [.hardware, .codec, .format, .allocation])
    #expect(KidsNativeContext(message: "PTS clock failed") == .timestamp)
    #expect(KidsNativeContext(message: "unknown private-token") == [])
}
