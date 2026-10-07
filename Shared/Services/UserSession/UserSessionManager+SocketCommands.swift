//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Combine
import Defaults
import Foundation
import JellyfinAPI
import SwiftfinAsyncStreams
import SwiftfinItemMetadata
import SwiftfinPlaybackPreparation
import SwiftfinTime
import UIKit

extension UserSessionManager {
    func observeSocketCommands() {
        #if os(tvOS)
        // Kids playback must pass its local catalog boundary and session budget. Remote queue/navigation commands are disabled.
        return
        #else
        $currentSession
            .sink { [weak self] session in self?.bindSocketCommands(to: session) }
            .store(in: &cancellables)
        Notifications[.didChangeServerConnection].publisher
            .sink { [weak self] _ in self?.bindSocketCommands(to: self?.currentSession) }
            .store(in: &cancellables)
        #endif
    }

    private func bindSocketCommands(to session: UserSession?) {
        guard let session else {
            socketCommands.cancel()
            socketItemRequest.cancel()
            socketTrailerRequest.cancel()
            return
        }
        let client = session.client
        let changed = socketCommands.replace(
            scope: [ObjectIdentifier(session), ObjectIdentifier(client)],
            makePublisher: {
                let socket = session.serverSocketManager
                return socket.playCommands.map(RemotePlaybackCommandPolicy.play)
                    .merge(
                        with: socket.playstateCommands.map(RemotePlaybackCommandPolicy.playstate),
                        socket.generalCommands.map(RemotePlaybackCommandPolicy.general)
                    )
                    .eraseToAnyPublisher()
            },
            isCurrent: { [weak self, weak session, weak client] in
                guard let self, let session, let client else { return false }
                return currentSession === session && session.client === client
            },
            receive: { [weak self] intent in self?.onReceive(intent: intent) }
        )
        if changed {
            socketItemRequest.cancel()
            socketTrailerRequest.cancel()
        }
    }

    private func onReceive(intent: RemotePlaybackIntent) {
        guard let currentSession else { return }
        switch intent {
        case let .playItem(id, source, ticks):
            playItem(id: id, mediaSourceID: source, startPositionTicks: ticks, userSession: currentSession)
        case .nextTrack:
            guard let manager = mediaPlayerManager, let next = manager.queue?.nextItem else { return }
            cancelPendingSocketPlayback()
            manager.playNewItem(provider: next)
        case .previousTrack:
            guard let manager = mediaPlayerManager, let previous = manager.queue?.previousItem else { return }
            cancelPendingSocketPlayback()
            manager.playNewItem(provider: previous)
        case .fastForward: mediaPlayerManager?.proxy?.jumpForward(Defaults[.VideoPlayer.jumpForwardInterval].rawValue)
        case .rewind: mediaPlayerManager?.proxy?.jumpBackward(Defaults[.VideoPlayer.jumpBackwardInterval].rawValue)
        case .pause: mediaPlayerManager?.setPlaybackRequestStatus(status: .paused)
        case .unpause: mediaPlayerManager?.setPlaybackRequestStatus(status: .playing)
        case .playPause: mediaPlayerManager?.togglePlayPause()
        case let .seek(ticks): mediaPlayerManager?.proxy?.setSeconds(.ticks(ticks))
        case .stop:
            cancelPendingSocketPlayback()
            mediaPlayerManager?.stop()
        case let .audioStream(index): mediaPlayerManager?.playbackItem?.selectedAudioStreamIndex = index
        case let .subtitleStream(index): mediaPlayerManager?.playbackItem?.selectedSubtitleStreamIndex = index
        case let .maxBitrate(bitrate): mediaPlayerManager?.setBitrate(bitrate: PlaybackBitrate(for: bitrate))
        case let .displayItem(id): routePublisher.send(.item(id: id))
        case let .trailers(id): playTrailers(itemID: id, userSession: currentSession)
        case .ignore: return
        }
    }

    private func cancelPendingSocketPlayback() {
        socketItemRequest.cancel()
        socketTrailerRequest.cancel()
    }

    private func playItem(
        id: String,
        mediaSourceID: String? = nil,
        startPositionTicks: Int? = nil,
        userSession: UserSession
    ) {
        cancelPendingSocketPlayback()
        let metadata = userSession.itemMetadata
        let logger = self.logger
        socketItemRequest.replace(operation: {
            do {
                return try await metadata.item(id: id)
            } catch {
                if !(error is CancellationError) {
                    logger.error("Unable to play item from socket command", metadata: ["error": .string(error.localizedDescription)])
                }
                throw error
            }
        }, receive: { [weak self, weak userSession] item in
            guard let self, let userSession else { return }
            guard (try? metadata.checkBinding()) != nil else { return }
            let source = item.mediaSources?.first { $0.id == mediaSourceID }
            guard var provider = item.getPlaybackItemProvider(userSession: userSession, mediaSource: source) else { return }
            if let startPositionTicks {
                provider = provider.modifyingItem { item in
                    if item.userData == nil {
                        item.userData = UserItemDataDto(key: "")
                    }
                    item.userData?.playbackPositionTicks = startPositionTicks
                }
            }
            if hasActivePlayback, let mediaPlayerManager {
                mediaPlayerManager.playNewItem(provider: provider)
            } else {
                routePublisher.send(.videoPlayer(provider: provider))
            }
        })
    }

    private func playTrailers(itemID: String, userSession: UserSession) {
        cancelPendingSocketPlayback()
        let catalog = userSession.mediaCatalog
        let metadata = userSession.itemMetadata
        let logger = self.logger
        socketTrailerRequest.replace(operation: {
            do {
                let trailers = try await catalog.localTrailers(itemID: itemID)
                try catalog.checkBinding()
                if let id = trailers.first?.id {
                    return .localItem(id)
                }
                let item = try await metadata.item(id: itemID)
                try metadata.checkBinding()
                guard let url = item.remoteTrailers?.first?.url else { throw CancellationError() }
                return .external(url)
            } catch {
                if !(error is CancellationError) {
                    logger.error("Unable to play trailers from socket command", metadata: ["error": .string(error.localizedDescription)])
                }
                throw error
            }
        }, receive: { [weak self, weak userSession] target in
            guard let self, let userSession, (try? catalog.checkBinding()) != nil else { return }
            switch target {
            case let .localItem(id): playItem(id: id, userSession: userSession)
            case let .external(urlString):
                #if os(tvOS)
                guard let externalURL = ExternalTrailerURL(string: urlString), externalURL.canBeOpened else { return }
                UIApplication.shared.open(externalURL.deepLink)
                #else
                guard let url = URL(string: urlString), UIApplication.shared.canOpenURL(url) else { return }
                UIApplication.shared.open(url)
                #endif
            }
        })
    }
}
