//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import os
@testable import SwiftfinNativePlayback
import Testing
import VideoToolbox

private final class HardwareProbeReceipt: Sendable {
    let calls = OSAllocatedUnfairLock(initialState: [String]())
    func record(_ value: String) {
        calls.withLock { $0.append(value) }
    }
}

struct HardwareReaderContracts {
    @Test
    func `semantic codec mapping retains all five native constants`() {
        #expect(HardwareVideoCodec.h264.nativeType == kCMVideoCodecType_H264)
        #expect(HardwareVideoCodec.hevc.nativeType == kCMVideoCodecType_HEVC)
        #expect(HardwareVideoCodec.av1.nativeType == kCMVideoCodecType_AV1)
        #expect(HardwareVideoCodec.vp9.nativeType == kCMVideoCodecType_VP9)
        #expect(HardwareVideoCodec.dolbyVisionHEVC.nativeType == kCMVideoCodecType_DolbyVisionHEVC)
    }

    @Test
    func `reader construction and single field reads do not eagerly probe hardware`() {
        let receipt = HardwareProbeReceipt()
        let reader = NativePlaybackHardwareReader(hdr: { receipt.record("hdr")
            return true
        }, gpuName: { receipt.record("gpu")
            return "synthetic-gpu"
        }, codec: { value in receipt.record(String(describing: value))
            return value == .hevc
        })
        #expect(receipt.calls.withLock { $0.isEmpty })
        #expect(reader.supports(.hevc))
        #expect(receipt.calls.withLock { $0 } == ["hevc"])
        #expect(reader.isHDRCapable && reader.gpuName == "synthetic-gpu")
        #expect(receipt.calls.withLock { $0 } == ["hevc", "hdr", "gpu"])
    }

    @Test
    func `missing gpu remains optional and codec inputs reach the exact reader`() {
        let receipt = HardwareProbeReceipt()
        let reader = NativePlaybackHardwareReader(
            hdr: { false },
            gpuName: { nil },
            codec: { value in receipt.record(String(describing: value))
                return value == .h264
            }
        )
        #expect(!reader.isHDRCapable && reader.gpuName == nil)
        for codec in HardwareVideoCodec.allCases {
            #expect(reader.supports(codec) == (codec == .h264))
        }
        #expect(receipt.calls.withLock { $0 } == ["h264", "hevc", "av1", "vp9", "dolbyVisionHEVC"])
    }

    @Test
    func `checked sendable readers retain injected behavior across tasks`() async {
        let reader = NativePlaybackHardwareReader(hdr: { true }, gpuName: { nil }, codec: { $0 == .av1 })
        let values = await Task.detached { (reader.isHDRCapable, reader.gpuName, reader.supports(.av1), reader.supports(.vp9)) }.value
        #expect(values.0 && values.1 == nil && values.2 && !values.3)
    }
}
