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

@MainActor
protocol NowPlayingOutput: AnyObject {
    var info: [String: Any]? { get set }
    var playing: Bool { get set }
    func install(
        _ command: NowPlayableCommand,
        handler: @escaping @MainActor @Sendable (NowPlayableCommand, NowPlayableCommand.Event) -> MPRemoteCommandHandlerStatus
    ) -> Any
    func remove(_ command: NowPlayableCommand, target: Any)
    func enable(_ command: NowPlayableCommand, value: Bool)
}

@MainActor
private final class SystemNowPlayingOutput: NowPlayingOutput {
    var info: [String: Any]? {
        get { MPNowPlayingInfoCenter.default().nowPlayingInfo }
        set { MPNowPlayingInfoCenter.default().nowPlayingInfo = newValue }
    }

    var playing: Bool {
        get { MPNowPlayingInfoCenter.default().playbackState == .playing }
        set { MPNowPlayingInfoCenter.default().playbackState = newValue ? .playing : .paused }
    }

    func install(
        _ command: NowPlayableCommand,
        handler: @escaping @MainActor @Sendable (NowPlayableCommand, NowPlayableCommand.Event) -> MPRemoteCommandHandlerStatus
    ) -> Any {
        command.addHandler(handler)
    }

    func remove(_ command: NowPlayableCommand, target: Any) {
        command.remoteCommand.removeTarget(target)
    }

    func enable(_ command: NowPlayableCommand, value: Bool) {
        command.isEnabled(value)
    }
}

/// Owns the process-wide command leases and Now Playing publication authority.
@MainActor
final class NowPlayingRegistry {
    static let shared = NowPlayingRegistry(output: SystemNowPlayingOutput())
    let output: any NowPlayingOutput
    private var targets: [NowPlayableCommand: (owner: UUID, target: Any)] = [:]
    private var publicationOwner: UUID?
    init(output: any NowPlayingOutput) {
        self.output = output
    }

    func configure(
        owner: UUID,
        commands: [NowPlayableCommand],
        handler: @escaping @MainActor @Sendable (NowPlayableCommand, NowPlayableCommand.Event) -> MPRemoteCommandHandlerStatus
    ) {
        // A process has one current playback owner, even when its command set changes.
        for command in Array(targets.keys) {
            guard let previous = targets[command] else { continue }
            output.remove(command, target: previous.target)
            output.enable(command, value: false)
        }
        targets.removeAll()
        publicationOwner = owner
        for command in commands {
            if let previous = targets[command] {
                output.remove(command, target: previous.target)
            }
            let target = output.install(command) { [weak self] command, event in
                guard let self, self.publicationOwner == owner, self.targets[command]?.owner == owner,
                      event.isValid(for: command) else { return .commandFailed }
                return handler(command, event)
            }
            targets[command] = (owner, target)
            output.enable(command, value: true)
        }
    }

    func clear(owner: UUID) {
        for command in Array(targets.keys) {
            guard let lease = targets[command], lease.owner == owner else { continue }
            output.remove(command, target: lease.target)
            output.enable(command, value: false)
            targets.removeValue(forKey: command)
        }
        if publicationOwner == owner {
            publicationOwner = nil
        }
    }

    func publish(owner: UUID, info: [String: Any]) {
        guard publicationOwner == owner else { return }
        output.info = info
    }

    func publish(owner: UUID, playing: Bool) {
        guard publicationOwner == owner else { return }
        output.playing = playing
    }
}

/// Small app-facing interface; SDK callback objects and handler tokens stay internal.
@MainActor
public final class NowPlayingController {
    private let owner = UUID()
    private let registry: NowPlayingRegistry
    public convenience init() {
        self.init(registry: .shared)
    }

    init(registry: NowPlayingRegistry) {
        self.registry = registry
    }

    public func configure(
        _ commands: [NowPlayableCommand],
        handler: @escaping @MainActor @Sendable (NowPlayableCommand, NowPlayableCommand.Event) -> MPRemoteCommandHandlerStatus
    ) {
        registry.configure(owner: owner, commands: commands, handler: handler)
    }

    isolated deinit { registry.clear(owner: owner) }
    public func clearCommands() {
        registry.clear(owner: owner)
    }

    public func setMetadata(_ metadata: NowPlayableStaticMetadata) {
        var info: [String: Any] = [:]
        info[MPNowPlayingInfoPropertyMediaType] = metadata.mediaType.rawValue
        info[MPNowPlayingInfoPropertyIsLiveStream] = metadata.isLiveStream
        info[MPMediaItemPropertyTitle] = metadata.title
        info[MPMediaItemPropertyArtist] = metadata.artist
        info[MPMediaItemPropertyArtwork] = metadata.artwork
        info[MPMediaItemPropertyAlbumArtist] = metadata.albumArtist
        info[MPMediaItemPropertyAlbumTitle] = metadata.albumTitle
        registry.publish(owner: owner, info: info)
    }

    public func updatePlayback(playing: Bool, metadata: NowPlayableDynamicMetadata) {
        var info = registry.output.info ?? [:]
        func seconds(_ value: Duration) -> Float {
            Float(Double(value.components.seconds) + Double(value.components.attoseconds) * 1e-18)
        }
        info[MPMediaItemPropertyPlaybackDuration] = seconds(metadata.duration)
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = seconds(metadata.position)
        info[MPNowPlayingInfoPropertyPlaybackRate] = playing ? metadata.rate : Float(0)
        info[MPNowPlayingInfoPropertyDefaultPlaybackRate] = 1.0
        info[MPNowPlayingInfoPropertyCurrentLanguageOptions] = metadata.currentLanguageOptions
        info[MPNowPlayingInfoPropertyAvailableLanguageOptions] = metadata.availableLanguageOptionGroups
        registry.publish(owner: owner, info: info)
        registry.publish(owner: owner, playing: playing)
    }
}
