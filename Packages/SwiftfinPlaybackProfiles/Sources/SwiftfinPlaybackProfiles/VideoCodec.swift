//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation

public enum VideoCodec: String, CaseIterable, Codable, Sendable {

    case av1
    case dv
    case dirac
    case ffv1
    case flv1
    case h261
    case h263
    case h264
    case hevc
    case mjpeg
    case mpeg1video
    case mpeg2video
    case mpeg4
    case msmpeg4v1
    case msmpeg4v2
    case msmpeg4v3
    case prores
    case theora
    case vc1
    case vp8
    case vp9
    case vvc
    case wmv1
    case wmv2
    case wmv3
}
