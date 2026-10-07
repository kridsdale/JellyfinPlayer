//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import AVFoundation
import Metal
import VideoToolbox

public enum HardwareVideoCodec: CaseIterable, Sendable {
    case h264
    case hevc
    case av1
    case vp9
    case dolbyVisionHEVC

    var nativeType: CMVideoCodecType {
        switch self {
        case .h264: kCMVideoCodecType_H264
        case .hevc: kCMVideoCodecType_HEVC
        case .av1: kCMVideoCodecType_AV1
        case .vp9: kCMVideoCodecType_VP9
        case .dolbyVisionHEVC: kCMVideoCodecType_DolbyVisionHEVC
        }
    }
}

/// Lazy native probes. Construction performs no hardware query, and reading one
/// property does not probe unrelated codecs. Tests inject synthetic readers.
public struct NativePlaybackHardwareReader: Sendable {
    private let readHDR: @Sendable () -> Bool
    private let readGPU: @Sendable () -> String?
    private let readCodec: @Sendable (HardwareVideoCodec) -> Bool

    public init() {
        self.init(
            hdr: { AVPlayer.eligibleForHDRPlayback },
            gpuName: { MTLCreateSystemDefaultDevice()?.name },
            codec: { VTIsHardwareDecodeSupported($0.nativeType) }
        )
    }

    public init(
        hdr: @escaping @Sendable () -> Bool,
        gpuName: @escaping @Sendable () -> String?,
        codec: @escaping @Sendable (HardwareVideoCodec) -> Bool
    ) {
        readHDR = hdr
        readGPU = gpuName
        readCodec = codec
    }

    public var isHDRCapable: Bool {
        readHDR()
    }

    public var gpuName: String? {
        readGPU()
    }

    public func supports(_ codec: HardwareVideoCodec) -> Bool {
        readCodec(codec)
    }
}
