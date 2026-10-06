//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation

public enum SubtitleFormat: String, CaseIterable, Codable, Sendable {

    case ass
    case cc_dec
    case dvdsub
    case dvbsub
    case libzvbi_teletextdec
    case mov_text
    case mpl2
    case pjs
    case pgssub
    case realtext
    case sami
    case ssa
    case subrip
    case subviewer
    case subviewer1
    case text
    case ttml
    case vplayer
    case vtt
    case xsub

    public init?(url: URL) {
        let fileExtension = url.pathExtension.lowercased()

        if let value = SubtitleFormat.allCases.first(where: { $0.fileExtension == fileExtension }) {
            self = value
        } else {
            return nil
        }
    }

    /// Gets the file extension for this subtitle format
    public var fileExtension: String {
        switch self {
        case .ass:
            "ass"
        case .cc_dec:
            "608"
        case .dvdsub:
            "sub"
        case .dvbsub:
            "dvbsub"
        case .libzvbi_teletextdec:
            "txt"
        case .mov_text:
            "tx3g"
        case .mpl2:
            "mpl"
        case .pjs:
            "pjs"
        case .pgssub:
            "sup"
        case .realtext:
            "rt"
        case .sami:
            "smi"
        case .ssa:
            "ssa"
        case .subrip:
            "srt"
        case .subviewer:
            "sub"
        case .subviewer1:
            "sub"
        case .text:
            "txt"
        case .ttml:
            "ttml"
        case .vplayer:
            "txt"
        case .vtt:
            "vtt"
        case .xsub:
            "xsub"
        }
    }

    /// Gets the appropriate UTType for this subtitle format

    /// Whether this format is a text-based subtitle
    public var isText: Bool {
        switch self {
        case .ass, .cc_dec, .libzvbi_teletextdec, .mov_text,
             .mpl2, .pjs, .realtext, .sami, .ssa, .subrip, .subviewer,
             .subviewer1, .text, .ttml, .vplayer, .vtt:
            true
        case .dvdsub, .dvbsub, .pgssub, .xsub:
            false
        }
    }
}
