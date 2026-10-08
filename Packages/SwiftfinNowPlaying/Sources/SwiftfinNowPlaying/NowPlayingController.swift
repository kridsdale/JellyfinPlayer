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
    private struct Authority: Equatable {
        let owner: UUID
        let epoch: UUID
    }

    private struct Lease {
        let authority: Authority
        let target: Any
    }

    private var targets: [NowPlayableCommand: Lease] = [:]
    private var publication: Authority?
    init(output: any NowPlayingOutput) {
        self.output = output
    }

    func configure(
        owner: UUID,
        commands: [NowPlayableCommand],
        handledByInterface: Set<NowPlayableCommand> = [],
        handler: @escaping @MainActor @Sendable (NowPlayableCommand, NowPlayableCommand.Event) -> MPRemoteCommandHandlerStatus
    ) {
        let authority = Authority(owner: owner, epoch: UUID())
        let previous = targets
        targets = [:]
        publication = authority
        retire(previous)
        for command in commands {
            guard publication == authority else { return }
            if let previous = targets.removeValue(forKey: command) {
                retire([command: previous])
                guard publication == authority else { return }
            }
            let target = output.install(command) { [weak self] command, event in
                guard let self, self.publication == authority, self.targets[command]?.authority == authority,
                      event.isValid(for: command) else { return .commandFailed }
                // The visible native interface performs this command once.
                if handledByInterface.contains(command) {
                    return .success
                }
                return handler(command, event)
            }
            guard publication == authority else {
                // Reentrant replacement must not leave an orphan registration.
                output.remove(command, target: target)
                return
            }
            targets[command] = Lease(authority: authority, target: target)
            output.enable(command, value: true)
        }
    }

    private func retire(_ previous: [NowPlayableCommand: Lease]) {
        for (command, lease) in previous {
            output.remove(command, target: lease.target)
            // Cleanup only owns its captured token, never a replacement target.
            if targets[command] == nil {
                output.enable(command, value: false)
            }
        }
    }

    func clear(owner: UUID) {
        let previous = targets.filter { $0.value.authority.owner == owner }
        for command in previous.keys {
            targets.removeValue(forKey: command)
        }
        if publication?.owner == owner {
            publication = nil
        }
        retire(previous)
    }

    func publish(owner: UUID, info: [String: Any]) {
        guard publication?.owner == owner else { return }
        output.info = info
    }

    /// Capture one lease before reading the shared center and retain it through
    /// both metadata and playback-state writes, including reentrant SDK effects.
    func update(owner: UUID, playing: Bool, transform: (inout [String: Any]) -> Void) {
        guard let authority = publication, authority.owner == owner else { return }
        var info = output.info ?? [:]
        guard publication == authority else { return }
        transform(&info)
        guard publication == authority else { return }
        output.info = info
        guard publication == authority else { return }
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
        handledByInterface: Set<NowPlayableCommand> = [],
        handler: @escaping @MainActor @Sendable (NowPlayableCommand, NowPlayableCommand.Event) -> MPRemoteCommandHandlerStatus
    ) {
        registry.configure(owner: owner, commands: commands, handledByInterface: handledByInterface, handler: handler)
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
        registry.update(owner: owner, playing: playing) { info in
            func seconds(_ value: Duration) -> Float {
                Float(Double(value.components.seconds) + Double(value.components.attoseconds) * 1e-18)
            }
            info[MPMediaItemPropertyPlaybackDuration] = seconds(metadata.duration)
            info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = seconds(metadata.position)
            info[MPNowPlayingInfoPropertyPlaybackRate] = playing ? metadata.rate : Float(0)
            info[MPNowPlayingInfoPropertyDefaultPlaybackRate] = 1.0
            info[MPNowPlayingInfoPropertyCurrentLanguageOptions] = metadata.currentLanguageOptions
            info[MPNowPlayingInfoPropertyAvailableLanguageOptions] = metadata.availableLanguageOptionGroups
        }
    }
}
