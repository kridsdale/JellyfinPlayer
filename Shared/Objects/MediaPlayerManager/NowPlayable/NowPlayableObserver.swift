//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Combine
import Foundation
import Logging
import MediaPlayer
import Nuke
import SwiftVLC

// TODO: ensure proper state handling
//       - manager states
//       - playback request states
// TODO: have MediaPlayerItem report supported commands

@MainActor
class NowPlayableObserver: ViewModel, MediaPlayerObserver {

    private var defaultRegisteredCommands: [NowPlayableCommand] {
        [
            .play,
            .pause,
            .togglePausePlay,
            .skipBackward,
            .skipForward,
            .changePlaybackPosition,
            // TODO: only register next/previous if there is a queue
//            .nextTrack,
//            .previousTrack,
        ]
    }

    private var itemImageCancellable: AnyCancellable?
    private var audioOwner: UUID?
    private var audioActivation: Task<Void, Error>?
    private var playbackRequestStateBeforeInterruption: MediaPlayerManager.PlaybackRequestStatus = .playing

    weak var manager: MediaPlayerManager? {
        didSet {
            guard oldValue !== manager else { return }
            handleStopAction(draining: (oldValue?.proxy as? VLCMediaPlayerProxy)?.player)
            guard let manager else { return }
            setup(with: manager)
        }
    }

    private func setup(with manager: MediaPlayerManager) {
        let owner = UUID()
        audioOwner = owner
        audioActivation = PlaybackAudioSession.shared.acquire(owner)

        cancellables = []

        manager.actions
            .sink { [weak self] newValue in self?.actionDidChange(newValue) }
            .store(in: &cancellables)

        manager.$playbackItem
            .sink { [weak self] newValue in self?.playbackItemDidChange(newValue) }
            .store(in: &cancellables)

        manager.$playbackRequestStatus
            .sink { [weak self] newValue in self?.playbackRequestStatusDidChange(newValue) }
            .store(in: &cancellables)

        manager.secondsBox.$value
            .sink { [weak self] newValue in self?.secondsDidChange(newValue) }
            .store(in: &cancellables)

        Notifications[.avAudioSessionInterruption]
            .publisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] i in
                self?.handleInterruption(type: i.0, options: i.1)
            }
            .store(in: &cancellables)

        configureRemoteCommands(defaultRegisteredCommands, commandHandler: { [weak self] command, event in
            guard let self, self.audioOwner == owner else { return .commandFailed }
            return self.handleCommand(command: command, event: event)
        })
    }

    private func playbackRequestStatusDidChange(_ newStatus: MediaPlayerManager.PlaybackRequestStatus) {
        handleNowPlayablePlaybackChange(
            playing: newStatus == .playing,
            metadata: .init(
                position: manager?.seconds ?? .zero,
                duration: manager?.item.runtime ?? .zero
            )
        )
    }

    private func secondsDidChange(_ newSeconds: Duration) {
        // Seeking while paused changes time without changing transport state.
        handleNowPlayablePlaybackChange(
            playing: manager?.playbackRequestStatus == .playing,
            metadata: .init(
                position: newSeconds,
                duration: manager?.item.runtime ?? .zero
            )
        )
    }

    private func actionDidChange(_ newAction: MediaPlayerManager._Action) {
        switch newAction {
        case .stop, .error:
            handleStopAction(draining: (manager?.proxy as? VLCMediaPlayerProxy)?.player)
        default: ()
        }
    }

    // TODO: remove and respond to manager action publisher instead
    // TODO: register different commands based on item capabilities
    private func playbackItemDidChange(_ newItem: MediaPlayerItem?) {
        itemImageCancellable?.cancel()
        itemImageCancellable = nil
        guard let newItem else { return }

        setNowPlayingMetadata(newItem.baseItem.nowPlayableStaticMetadata())

        itemImageCancellable = Task {
            let currentBaseItem = newItem.baseItem
            guard let image = await newItem.thumbnailProvider?() else { return }
            guard !Task.isCancelled, audioOwner != nil,
                  manager?.state != .stopped, manager?.state != .error,
                  manager?.item.id == currentBaseItem.id else { return }

            await MainActor.run {
                setNowPlayingMetadata(
                    currentBaseItem.nowPlayableStaticMetadata(image)
                )
            }
        }
        .asAnyCancellable()

        handleNowPlayablePlaybackChange(
            playing: true,
            metadata: .init(
                position: manager?.seconds ?? .zero,
                duration: manager?.item.runtime ?? .zero
            )
        )
    }

    /// The native player awaits activation before opening audio/video output.
    func prepareForPlayback() async throws {
        guard let audioActivation, audioOwner != nil else { throw CancellationError() }
        try await audioActivation.value
        try Task.checkCancellation()
        guard audioOwner != nil else { throw CancellationError() }
    }

    private func handleStopAction(draining player: Player?) {
        cancellables = []
        itemImageCancellable?.cancel()
        itemImageCancellable = nil
        guard let owner = audioOwner else { return }
        audioOwner = nil
        audioActivation = nil
        for command in defaultRegisteredCommands {
            command.removeHandler()
        }
        PlaybackAudioSession.shared.release(owner) {
            guard let player else { return true }
            // This manager is terminal. Full teardown detaches the drawable and
            // awaits native-handle release; merely waiting for Stop left paused
            // simulator outputs draining until the SDK's ten-second ceiling.
            await player.shutdown()
            return player.state == .idle
        }
    }

    private func handleInterruption(
        type: AVAudioSession.InterruptionType,
        options: AVAudioSession.InterruptionOptions
    ) {
        guard let manager, let owner = audioOwner,
              manager.state != .stopped, manager.state != .error else { return }
        switch type {
        case .began:
            PlaybackAudioSession.shared.wasInterrupted()
            playbackRequestStateBeforeInterruption = manager.playbackRequestStatus
            manager.setPlaybackRequestStatus(status: .paused)
        case .ended:
            let shouldResume = playbackRequestStateBeforeInterruption == .playing && options.contains(.shouldResume)
            let activation = PlaybackAudioSession.shared.acquire(owner)
            audioActivation = activation
            Task { [weak self, weak manager] in
                do {
                    try await activation.value
                    guard let self, let manager, self.audioOwner == owner,
                          manager.state != .stopped, manager.state != .error else { return }
                    manager.setPlaybackRequestStatus(status: shouldResume ? .playing : .paused)
                } catch {
                    guard let self, self.audioOwner == owner else { return }
                    self.logger.error("Audio session reactivation failed")
                    await manager?.stop()
                }
            }
        @unknown default: ()
        }
    }

    @MainActor
    private func handleCommand(
        command: NowPlayableCommand,
        event: NowPlayableCommand.Event
    ) -> MPRemoteCommandHandlerStatus {
        guard let manager, audioOwner != nil,
              manager.state != .stopped, manager.state != .error else { return .commandFailed }
        switch command {
        case .pause:
            manager.setPlaybackRequestStatus(status: .paused)
        case .play:
            manager.setPlaybackRequestStatus(status: .playing)
        case .togglePausePlay:
            manager.togglePlayPause()
        case .skipBackward:
            guard let interval = event.interval else { return .commandFailed }
            manager.proxy?.jumpBackward(.seconds(interval))
        case .skipForward:
            guard let interval = event.interval else { return .commandFailed }
            manager.proxy?.jumpForward(.seconds(interval))
        case .changePlaybackPosition:
            guard let position = event.positionTime else { return .commandFailed }
            manager.proxy?.setSeconds(Duration.seconds(position))
        case .nextTrack:
            guard let nextItem = manager.queue?.nextItem else { return .commandFailed }
            manager.playNewItem(provider: nextItem)
        case .previousTrack:
            guard let previousItem = manager.queue?.previousItem else { return .commandFailed }
            manager.playNewItem(provider: previousItem)
        default: ()
        }

        return .success
    }

    private func handleNowPlayablePlaybackChange(
        playing: Bool,
        metadata: NowPlayableDynamicMetadata
    ) {
        setNowPlayingPlaybackInfo(metadata, playing: playing)
        MPNowPlayingInfoCenter.default().playbackState = playing ? .playing : .paused
    }

    private func configureRemoteCommands(
        _ commands: [NowPlayableCommand],
        commandHandler: @escaping @MainActor @Sendable (NowPlayableCommand, NowPlayableCommand.Event) -> MPRemoteCommandHandlerStatus
    ) {
        guard commands.isNotEmpty else { return }

        for command in commands {
            command.addHandler(commandHandler)
            command.isEnabled(true)
        }
    }

    private func setNowPlayingMetadata(_ metadata: NowPlayableStaticMetadata) {

        let nowPlayingInfoCenter = MPNowPlayingInfoCenter.default()
        var nowPlayingInfo: [String: Any] = [:]

        nowPlayingInfo[MPNowPlayingInfoPropertyMediaType] = metadata.mediaType.rawValue
        nowPlayingInfo[MPNowPlayingInfoPropertyIsLiveStream] = metadata.isLiveStream
        nowPlayingInfo[MPMediaItemPropertyTitle] = metadata.title
        nowPlayingInfo[MPMediaItemPropertyArtist] = metadata.artist
        nowPlayingInfo[MPMediaItemPropertyArtwork] = metadata.artwork
        nowPlayingInfo[MPMediaItemPropertyAlbumArtist] = metadata.albumArtist
        nowPlayingInfo[MPMediaItemPropertyAlbumTitle] = metadata.albumTitle

        nowPlayingInfoCenter.nowPlayingInfo = nowPlayingInfo
    }

    private func setNowPlayingPlaybackInfo(_ metadata: NowPlayableDynamicMetadata, playing: Bool) {

        let nowPlayingInfoCenter = MPNowPlayingInfoCenter.default()
        var nowPlayingInfo: [String: Any] = nowPlayingInfoCenter.nowPlayingInfo ?? [:]

        nowPlayingInfo[MPMediaItemPropertyPlaybackDuration] = Float(metadata.duration.seconds)
        nowPlayingInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = Float(metadata.position.seconds)
        nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] = playing ? metadata.rate : 0
        nowPlayingInfo[MPNowPlayingInfoPropertyDefaultPlaybackRate] = 1.0
        nowPlayingInfo[MPNowPlayingInfoPropertyCurrentLanguageOptions] = metadata.currentLanguageOptions
        nowPlayingInfo[MPNowPlayingInfoPropertyAvailableLanguageOptions] = metadata.availableLanguageOptionGroups

        nowPlayingInfoCenter.nowPlayingInfo = nowPlayingInfo
    }
}
