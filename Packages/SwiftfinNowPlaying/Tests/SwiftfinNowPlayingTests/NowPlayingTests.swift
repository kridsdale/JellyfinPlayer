//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

// SPDX-License-Identifier: MPL-2.0
import Foundation
import MediaPlayer
@testable import SwiftfinNowPlaying
import Testing

@MainActor
private final class Output: NowPlayingOutput {
    final class Target {
        let handler: @MainActor @Sendable (NowPlayableCommand, NowPlayableCommand.Event) -> MPRemoteCommandHandlerStatus
        init(_ handler: @escaping @MainActor @Sendable (NowPlayableCommand, NowPlayableCommand.Event) -> MPRemoteCommandHandlerStatus) {
            self.handler = handler
        }
    }

    var info: [String: Any]?
    var playing = false
    var targets: [NowPlayableCommand: Target] = [:]
    var removed = 0
    var enabled = Set<NowPlayableCommand>()
    func install(
        _ command: NowPlayableCommand,
        handler: @escaping @MainActor @Sendable (NowPlayableCommand, NowPlayableCommand.Event) -> MPRemoteCommandHandlerStatus
    ) -> Any {
        let target = Target(handler)
        targets[command] = target
        return target
    }

    func remove(_ command: NowPlayableCommand, target: Any) {
        if targets[command] === (target as? Target) {
            targets.removeValue(forKey: command)
        }
        removed += 1
    }

    func enable(_ command: NowPlayableCommand, value: Bool) {
        if value {
            enabled.insert(command)
        } else {
            enabled.remove(command)
        }
    }
}

@Test @MainActor
func `paused timeline retains static metadata and reports rate zero`() {
    let output = Output(), registry = NowPlayingRegistry(output: output), controller = NowPlayingController(registry: registry)
    controller.configure([.play, .pause]) { _, _ in .success }
    controller.setMetadata(.init(mediaType: .video, title: "Approved fixture"))
    controller.updatePlayback(playing: false, metadata: .init(rate: 1.5, position: .milliseconds(123_450), duration: .seconds(600)))
    #expect(output.info?[MPMediaItemPropertyTitle] as? String == "Approved fixture")
    #expect(output.info?[MPNowPlayingInfoPropertyElapsedPlaybackTime] as? Float == 123.45)
    #expect(output.info?[MPNowPlayingInfoPropertyPlaybackRate] as? Float == 0)
    #expect(!output.playing)
    controller.updatePlayback(playing: true, metadata: .init(rate: 1.5, position: .seconds(124), duration: .seconds(600)))
    #expect(output.info?[MPNowPlayingInfoPropertyPlaybackRate] as? Float == 1.5)
    #expect(output.playing)
    controller.clearCommands()
}

@Test @MainActor
func `late former owner cannot clear replacement commands or overwrite its metadata`() {
    let output = Output(), registry = NowPlayingRegistry(output: output)
    let old = NowPlayingController(registry: registry), replacement = NowPlayingController(registry: registry)
    old.configure([.play, .pause]) { _, _ in .success }
    old.setMetadata(.init(mediaType: .video, title: "Old"))
    replacement.configure([.play, .pause]) { _, _ in .success }
    replacement.setMetadata(.init(mediaType: .video, title: "Replacement"))
    replacement.updatePlayback(playing: true, metadata: .init(position: .seconds(50), duration: .seconds(600)))
    let removed = output.removed
    old.clearCommands()
    old.setMetadata(.init(mediaType: .video, title: "Stale image result"))
    old.updatePlayback(playing: false, metadata: .init(position: .seconds(0), duration: .seconds(100)))
    #expect(output.removed == removed)
    #expect(output.enabled == [.play, .pause])
    #expect(output.info?[MPMediaItemPropertyTitle] as? String == "Replacement")
    #expect(output.info?[MPNowPlayingInfoPropertyElapsedPlaybackTime] as? Float == 50)
    #expect(output.playing)
    replacement.clearCommands()
}

@Test @MainActor
func `queued prior command is rejected after another owner acquires playback`() throws {
    let output = Output(), registry = NowPlayingRegistry(output: output)
    let old = NowPlayingController(registry: registry), replacement = NowPlayingController(registry: registry)
    var previousCalls = 0, currentCalls = 0
    old.configure([.play]) { _, _ in previousCalls += 1
        return .success
    }
    let stale = try #require(output.targets[.play])
    replacement.configure([.play]) { _, _ in currentCalls += 1
        return .success
    }
    #expect(stale.handler(.play, .init()) == .commandFailed)
    #expect(try #require(output.targets[.play]).handler(.play, .init()) == .success)
    #expect(previousCalls == 0)
    #expect(currentCalls == 1)
    replacement.clearCommands()
}

@Test @MainActor
func `new command set revokes old commands that it does not support`() throws {
    let output = Output(), registry = NowPlayingRegistry(output: output)
    let old = NowPlayingController(registry: registry), next = NowPlayingController(registry: registry)
    old.configure([.play, .nextTrack]) { _, _ in .success }
    let stale = try #require(output.targets[.nextTrack])
    next.configure([.play]) { _, _ in .success }
    #expect(output.targets[.nextTrack] == nil)
    #expect(output.enabled == [.play])
    #expect(stale.handler(.nextTrack, .init()) == .commandFailed)
    next.clearCommands()
}

@Test @MainActor
func `cleared controller rejects late commands and cannot publish new state`() throws {
    let output = Output(), registry = NowPlayingRegistry(output: output), controller = NowPlayingController(registry: registry)
    controller.configure([.play]) { _, _ in .success }
    let stale = try #require(output.targets[.play])
    controller.setMetadata(.init(mediaType: .video, title: "Current"))
    controller.clearCommands()
    controller.clearCommands()
    #expect(output.removed == 1)
    #expect(stale.handler(.play, .init()) == .commandFailed)
    controller.setMetadata(.init(mediaType: .video, title: "Late"))
    #expect(output.info?[MPMediaItemPropertyTitle] as? String == "Current")
}

@Test
func `immutable remote payload rejects nonfinite negative or absent positions`() {
    for value in [Double.nan, .infinity, -.infinity, -1] {
        #expect(!NowPlayableCommand.Event(interval: value).isValid(for: .skipForward))
        #expect(!NowPlayableCommand.Event(positionTime: value).isValid(for: .changePlaybackPosition))
    }
    #expect(!NowPlayableCommand.Event().isValid(for: .skipBackward))
    #expect(!NowPlayableCommand.Event().isValid(for: .changePlaybackPosition))
    #expect(NowPlayableCommand.Event(interval: 15).isValid(for: .skipForward))
    #expect(NowPlayableCommand.Event(positionTime: 0).isValid(for: .changePlaybackPosition))
    #expect(NowPlayableCommand.Event().isValid(for: .pause))
}
