//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation

public enum AudioCodec: String, CaseIterable, Codable, Sendable {

    case aac
    case ac3
    case amr_nb
    case amr_wb
    case dts
    case dts_hd
    case eac3
    case flac
    case alac
    case mlp
    case mp1
    case mp2
    case mp3
    case nellymoser
    case opus
    case pcm_alaw
    case pcm_bluray
    case pcm_dvd
    case pcm_mulaw
    case pcm_s16be
    case pcm_s16le
    case pcm_s24be
    case pcm_s24le
    case pcm_u8
    case speex
    case truehd
    case vorbis
    case wavpack
    case wmalossless
    case wmapro
    case wmav1
    case wmav2
}
