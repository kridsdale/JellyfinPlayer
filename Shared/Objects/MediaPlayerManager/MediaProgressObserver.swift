//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Combine
import Defaults
import FactoryKit
import Foundation
import JellyfinAPI
import SwiftfinAsyncStreams
import SwiftfinNetworking
import SwiftfinPlaybackReporting
import SwiftfinTime

/// Platform subscriptions feed one shared serialized reporting queue. Every
/// playback report retains the connection captured when this observer is made.
@MainActor
final class MediaProgressObserver: ViewModel, MediaPlayerObserver {
    private static var lastReporter: PlaybackReportQueue<PlaybackStateInfo>?
    private let transport: JellyfinTransport?
    private let timer = PokeIntervalTimer()
    private var reportClient: PlaybackReportingClient?
    private var reporter: PlaybackReportQueue<PlaybackStateInfo>?
    private var lastSnapshot: PlaybackStateInfo?
    private var ended = false
    private weak var item: MediaPlayerItem?
    private var lastPlaybackRequestStatus: MediaPlayerManager.PlaybackRequestStatus = .playing
    private var subscriptions = Set<AnyCancellable>()

    weak var manager: MediaPlayerManager? {
        didSet {
            subscriptions.removeAll()
            if let manager {
                setup(with: manager)
            } else {
                endPlaybackSession()
                timer.stop()
            }
        }
    }

    init(item: MediaPlayerItem) {
        self.item = item
        self.transport = Container.shared.currentUserSession()?.client
        super.init()
        configureReportClient(for: item)
    }

    private func configureReportClient(for item: MediaPlayerItem?) {
        guard let item, let id = item.baseItem.id, let transport else { reportClient = nil
            return
        }
        reportClient = PlaybackReportingClient(sender: transport, identity: .init(
            itemID: id, mediaSourceID: item.mediaSource.id, liveStreamID: item.mediaSource.liveStreamID,
            playSessionID: item.playSessionID, sessionID: item.playSessionID
        ))
    }

    private func snapshot() -> PlaybackStateInfo? {
        guard let item, let reportClient else { return nil }
        return reportClient.identity.snapshot(
            positionTicks: manager?.seconds.ticks,
            audio: item.selectedAudioStreamIndex,
            subtitle: item.selectedSubtitleStreamIndex,
            isPaused: lastPlaybackRequestStatus == .paused ? true : nil
        )
    }

    private func sendReport() {
        #if DEBUG
        guard Defaults[.sendProgressReports] else { return }
        #endif
        guard !ended, let snapshot = snapshot(), let reportClient else { return }
        lastSnapshot = snapshot
        if let reporter {
            reporter.update(snapshot)
        } else {
            let logger = self.logger
            let reporter = PlaybackReportQueue(initial: snapshot, after: Self.lastReporter) { event in
                do { try await reportClient.send(event.kind, snapshot: event.snapshot) }
                catch { logger.warning("Playback report failed")
                    throw error
                }
            }
            self.reporter = reporter
            Self.lastReporter = reporter
        }
    }

    private func endPlaybackSession() {
        guard !ended else { return }
        ended = true
        timer.stop()
        subscriptions.removeAll()
        if let snapshot = snapshot() ?? lastSnapshot {
            reporter?.finish(snapshot)
        }
        reporter = nil
        lastSnapshot = nil
    }

    private func playbackItemDidChange(_ newItem: MediaPlayerItem?) {
        timer.poke()
        guard newItem !== item else { return }
        endPlaybackSession()
    }

    private func playbackRequestStatusDidChange(_ status: MediaPlayerManager.PlaybackRequestStatus) {
        lastPlaybackRequestStatus = status
        timer.poke()
        if reporter != nil {
            sendReport()
        }
    }

    private func setup(with manager: MediaPlayerManager) {
        guard !ended else { return }
        timer.sink { [weak self] in self?.sendReport()
            self?.timer.poke()
        }.store(in: &subscriptions)
        manager.actions.sink { [weak self] action in
            switch action {
            case .stop, .error:
                self?.endPlaybackSession()
                self?.timer.stop()
                self?.subscriptions.removeAll()
                self?.item = nil
            default: break
            }
        }.store(in: &subscriptions)
        manager.$playbackItem.sink { [weak self] in self?.playbackItemDidChange($0) }.store(in: &subscriptions)
        manager.$playbackRequestStatus.sink { [weak self] in self?.playbackRequestStatusDidChange($0) }.store(in: &subscriptions)
        Notifications[.applicationWillTerminate].publisher.sink { [weak self] _ in
            self?.endPlaybackSession()
            self?.timer.stop()
        }.store(in: &subscriptions)
    }
}
