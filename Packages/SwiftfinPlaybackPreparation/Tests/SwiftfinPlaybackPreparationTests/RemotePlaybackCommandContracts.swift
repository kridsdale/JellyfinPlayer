//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import JellyfinAPI
import SwiftfinPlaybackPreparation
import Testing

struct RemotePlaybackCommandContracts {
    @Test
    func `all play kinds retain unsupported command behavior and default play now`() {
        for kind in PlayCommand.allCases {
            let result = RemotePlaybackCommandPolicy.play(.init(itemIDs: ["first"], playCommand: kind))
            let expected: RemotePlaybackIntent = switch kind {
            case .playNow: .playItem(id: "first", mediaSourceID: nil, startPositionTicks: nil)
            case .playNext: .nextTrack
            case .playLast: .previousTrack
            case .playInstantMix, .playShuffle: .ignore
            }
            #expect(result == expected)
        }
        #expect(RemotePlaybackCommandPolicy.play(.init(itemIDs: ["first"])) == .playItem(
            id: "first",
            mediaSourceID: nil,
            startPositionTicks: nil
        ))
    }

    @Test
    func `indices outside range fall back to first without integer overflow`() {
        for index in [Int.min, -1, 0, 2, Int.max] {
            #expect(RemotePlaybackCommandPolicy.play(.init(itemIDs: ["first", "second"], startIndex: index)) == .playItem(
                id: "first",
                mediaSourceID: nil,
                startPositionTicks: nil
            ))
        }
        #expect(RemotePlaybackCommandPolicy.play(.init(itemIDs: ["first", "second"], startIndex: 1)) == .playItem(
            id: "second",
            mediaSourceID: nil,
            startPositionTicks: nil
        ))
        #expect(RemotePlaybackCommandPolicy.play(.init(itemIDs: [])) == .ignore)
        #expect(RemotePlaybackCommandPolicy.play(.init()) == .ignore)
    }

    @Test
    func `media source optional signed position and empty item identity are forwarded exactly`() {
        for ticks in [Int.min, -1, 0, 1, Int.max] {
            #expect(RemotePlaybackCommandPolicy.play(.init(itemIDs: [""], mediaSourceID: "", startPositionTicks: ticks)) == .playItem(
                id: "",
                mediaSourceID: "",
                startPositionTicks: ticks
            ))
        }
    }

    @Test
    func `all playstate kinds map to existing native controls`() {
        let expected: [PlaystateCommand: RemotePlaybackIntent] = [
            .fastForward: .fastForward, .nextTrack: .nextTrack, .pause: .pause,
            .playPause: .playPause, .previousTrack: .previousTrack, .rewind: .rewind,
            .seek: .seek(ticks: 7), .stop: .stop, .unpause: .unpause
        ]
        #expect(expected.count == PlaystateCommand.allCases.count)
        for kind in PlaystateCommand.allCases {
            #expect(RemotePlaybackCommandPolicy.playstate(.init(command: kind, seekPositionTicks: 7)) == expected[kind])
        }
        #expect(RemotePlaybackCommandPolicy.playstate(.init()) == .ignore)
        #expect(RemotePlaybackCommandPolicy.playstate(.init(command: .seek)) == .ignore)
        #expect(RemotePlaybackCommandPolicy.playstate(.init(command: .seek, seekPositionTicks: -1)) == .seek(ticks: -1))
    }

    @Test
    func `all general commands retain the limited accepted control vocabulary`() {
        let expected: [GeneralCommandType: RemotePlaybackIntent] = [
            .setAudioStreamIndex: .audioStream(index: 12), .setSubtitleStreamIndex: .subtitleStream(index: 12),
            .setMaxStreamingBitrate: .maxBitrate(42), .displayContent: .displayItem(id: "item"),
            .playMediaSource: .playItem(id: "item", mediaSourceID: "source", startPositionTicks: nil),
            .playTrailers: .trailers(itemID: "item")
        ]
        for kind in GeneralCommandType.allCases {
            let command = GeneralCommand(
                arguments: ["Index": "12", "Bitrate": "42", "ItemId": "item", "MediaSourceId": "source"],
                name: kind
            )
            #expect(RemotePlaybackCommandPolicy.general(command) == expected[kind, default: .ignore])
        }
        #expect(RemotePlaybackCommandPolicy.general(.init()) == .ignore)
    }

    @Test
    func `numeric controls keep exact Int parsing missing keys signs and overflow`() {
        let inputs: [(String, Int?)] = [
            ("0", 0),
            ("-1", -1),
            ("+12", 12),
            (" 2", nil),
            ("2 ", nil),
            ("", nil),
            ("0x10", nil),
            ("1.0", nil),
            (String(Int.max), Int.max),
            (String(Int.max) + "0", nil)
        ]
        for (text, parsed) in inputs {
            #expect(RemotePlaybackCommandPolicy.general(.init(arguments: ["Index": text], name: .setAudioStreamIndex)) == parsed
                .map { .audioStream(index: $0) } ?? .ignore)
            #expect(RemotePlaybackCommandPolicy.general(.init(arguments: ["Index": text], name: .setSubtitleStreamIndex)) == parsed
                .map { .subtitleStream(index: $0) } ?? .ignore)
            #expect(RemotePlaybackCommandPolicy.general(.init(arguments: ["Bitrate": text], name: .setMaxStreamingBitrate)) == parsed
                .map { .maxBitrate($0) } ?? .ignore)
        }
        for kind in [GeneralCommandType.setAudioStreamIndex, .setSubtitleStreamIndex, .setMaxStreamingBitrate] {
            #expect(RemotePlaybackCommandPolicy.general(.init(arguments: ["index": "7", "bitrate": "12"], name: kind)) == .ignore)
            #expect(RemotePlaybackCommandPolicy.general(.init(name: kind)) == .ignore)
        }
    }

    @Test
    func `navigation and trailer identifiers are case sensitive and retain empty values`() {
        for kind in [GeneralCommandType.displayContent, .playMediaSource, .playTrailers] {
            #expect(RemotePlaybackCommandPolicy.general(.init(arguments: ["itemId": "item"], name: kind)) == .ignore)
            #expect(RemotePlaybackCommandPolicy.general(.init(name: kind)) == .ignore)
        }
        #expect(RemotePlaybackCommandPolicy.general(.init(arguments: ["ItemId": ""], name: .displayContent)) == .displayItem(id: ""))
        #expect(RemotePlaybackCommandPolicy
            .general(.init(arguments: ["ItemId": "", "MediaSourceId": ""], name: .playMediaSource)) == .playItem(
                id: "",
                mediaSourceID: "",
                startPositionTicks: nil
            ))
        #expect(RemotePlaybackCommandPolicy.general(.init(arguments: ["ItemId": ""], name: .playTrailers)) == .trailers(itemID: ""))
    }

    @Test
    func `interpreted command transfers between executors as an immutable value`() async {
        let result = await Task.detached {
            RemotePlaybackCommandPolicy.general(.init(arguments: ["ItemId": "item", "MediaSourceId": "source"], name: .playMediaSource))
        }.value
        #expect(result == .playItem(id: "item", mediaSourceID: "source", startPositionTicks: nil))
    }
}
