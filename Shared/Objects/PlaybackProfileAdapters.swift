//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Defaults
import Foundation
import JellyfinAPI
import SwiftfinCollections
import SwiftfinLocalization
import SwiftfinPlaybackProfiles
import SwiftfinStoredValues
import UniformTypeIdentifiers

extension VideoCodec: Displayable {
    var displayTitle: String {
        switch self {
        case .av1:
            L10n.av1
        case .dv:
            L10n.dv
        case .dirac:
            L10n.dirac
        case .ffv1:
            L10n.ffv1
        case .flv1:
            L10n.flv1
        case .h261:
            L10n.h261
        case .h263:
            L10n.h263
        case .h264:
            L10n.h264
        case .hevc:
            L10n.hevc
        case .mjpeg:
            L10n.mjpeg
        case .mpeg1video:
            L10n.mpeg1Video
        case .mpeg2video:
            L10n.mpeg2Video
        case .mpeg4:
            L10n.mpeg4
        case .msmpeg4v1:
            L10n.msMpeg4V1
        case .msmpeg4v2:
            L10n.msMpeg4V2
        case .msmpeg4v3:
            L10n.msMpeg4V3
        case .prores:
            L10n.proRes
        case .theora:
            L10n.theora
        case .vc1:
            L10n.vc1
        case .vp8:
            L10n.vp8
        case .vp9:
            L10n.vp9
        case .vvc:
            L10n.vvc
        case .wmv1:
            L10n.wmv1
        case .wmv2:
            L10n.wmv2
        case .wmv3:
            L10n.wmv3
        }
    }
}

extension AudioCodec: Displayable {
    var displayTitle: String {
        switch self {
        case .aac:
            L10n.aac
        case .ac3:
            L10n.ac3
        case .amr_nb:
            L10n.amrNB
        case .amr_wb:
            L10n.amrWB
        case .dts:
            L10n.dts
        case .dts_hd:
            L10n.dtsHD
        case .eac3:
            L10n.eac3
        case .flac:
            L10n.flac
        case .alac:
            L10n.alac
        case .mlp:
            L10n.mlp
        case .mp1:
            L10n.mp1
        case .mp2:
            L10n.mp2
        case .mp3:
            L10n.mp3
        case .nellymoser:
            L10n.nellymoser
        case .opus:
            L10n.opus
        case .pcm_alaw:
            L10n.pcmALAW
        case .pcm_bluray:
            L10n.pcmBluray
        case .pcm_dvd:
            L10n.pcmDVD
        case .pcm_mulaw:
            L10n.pcmMULAW
        case .pcm_s16be:
            L10n.pcmS16BE
        case .pcm_s16le:
            L10n.pcmS16LE
        case .pcm_s24be:
            L10n.pcmS24BE
        case .pcm_s24le:
            L10n.pcmS24LE
        case .pcm_u8:
            L10n.pcmU8
        case .speex:
            L10n.speex
        case .truehd:
            L10n.trueHD
        case .vorbis:
            L10n.vorbis
        case .wavpack:
            L10n.wavPack
        case .wmalossless:
            L10n.wmaLossless
        case .wmapro:
            L10n.wmaPro
        case .wmav1:
            L10n.wmaV1
        case .wmav2:
            L10n.wmaV2
        }
    }
}

extension SubtitleFormat: Displayable {
    var displayTitle: String {
        switch self {
        case .ass:
            L10n.ass
        case .cc_dec:
            L10n.eia608
        case .dvdsub:
            L10n.dvdSubtitle
        case .dvbsub:
            L10n.dvbSubtitle
        case .libzvbi_teletextdec:
            L10n.dvbTeletext
        case .mov_text:
            L10n.mpeg4TimedText
        case .mpl2:
            L10n.mpl2
        case .pjs:
            L10n.phoenixSubtitle
        case .pgssub:
            L10n.pgsSubtitle
        case .realtext:
            L10n.realText
        case .sami:
            L10n.smi
        case .ssa:
            L10n.ssa
        case .subrip:
            L10n.srt
        case .subviewer:
            L10n.subViewer
        case .subviewer1:
            L10n.subViewer1
        case .text:
            L10n.txt
        case .ttml:
            L10n.ttml
        case .vplayer:
            L10n.vPlayer
        case .vtt:
            L10n.webVTT
        case .xsub:
            L10n.xsub
        }
    }
}

extension SubtitleFormat {
    var utType: UTType? {
        switch self {
        case .libzvbi_teletextdec, .text, .vplayer:
            UTType.plainText
        default:
            UTType(filenameExtension: fileExtension)
        }
    }
}

extension MediaContainer: Displayable {
    var displayTitle: String {
        switch self {
        case .avi:
            L10n.avi
        case .flv:
            L10n.flv
        case .m4v:
            L10n.m4v
        case .mkv:
            L10n.mkv
        case .mov:
            L10n.mov
        case .mp4:
            L10n.mp4
        case .mpegts:
            L10n.mpegTS
        case .ts:
            L10n.ts
        case .threeG2:
            L10n.threeG2
        case .threeGP:
            L10n.threeGP
        case .webm:
            L10n.webm
        }
    }
}

extension PlaybackResolution: Displayable {
    var displayTitle: String {
        switch self {
        case .max:
            return L10n.maximum
        default:
            guard rawValue > 0 else { return L10n.unknown }
            return "\(rawValue.description)p"
        }
    }
}

extension CustomDeviceProfileAction: Displayable {
    var displayTitle: String {
        switch self {
        case .add:
            L10n.add
        case .replace:
            L10n.replace
        }
    }
}

extension PlaybackCompatibility: Displayable {
    var displayTitle: String {
        switch self {
        case .auto:
            L10n.auto
        case .mostCompatible:
            L10n.compatible
        case .directPlay:
            L10n.directPlay
        case .custom:
            L10n.custom
        }
    }
}
