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
import KidsDiagnostics
import KidsPlayback
import SwiftfinAsyncStreams
import SwiftfinPlaybackReporting

// SPDX-License-Identifier: MPL-2.0
import SwiftfinTime

/// Reports only after the kids controller proves decoded video and an advancing
/// clock. The transport captures its client once; a queued report can never be
/// redirected to a different account by a later ViewModel session change.
@MainActor
final class KidsMediaProgressObserver: ViewModel, MediaPlayerObserver {
    // Only one tail is retained. Completed tasks release their captured clients;
    // the next worker captures a task handle, never a previous observer/item.
    private static var lastReporter: KidsPlaybackReporter<PlaybackStateInfo>?
    private weak var item: MediaPlayerItem?
    private let reportClient: PlaybackReportingClient
    private var reporter: KidsPlaybackReporter<PlaybackStateInfo>?
    private var subscriptions = Set<AnyCancellable>()
    private var lastSnapshot: PlaybackStateInfo?
    private var ended = false

    weak var manager: MediaPlayerManager? {
        didSet {
            subscriptions.removeAll()
            guard let manager else { finish()
                return
            }
            setup(with: manager)
        }
    }

    init(item: MediaPlayerItem, reportClient: PlaybackReportingClient) {
        self.item = item
        self.reportClient = reportClient
        super.init()
    }

    func beginPlayback() {
        guard !ended, reporter == nil, let snapshot = snapshot() else { return }
        #if DEBUG
        guard Defaults[.sendProgressReports] else { return }
        #endif
        let reportClient = self.reportClient
        lastSnapshot = snapshot
        let logger = self.logger
        reporter = KidsPlaybackReporter(initial: snapshot, after: Self.lastReporter) { event in
            let endpoint: KidsPerformanceEndpoint = switch event.kind {
            case .start: .playbackStart
            case .progress: .playbackProgress
            case .stop: .playbackStop
            }
            let trace = KidsPerformance.begin(.playbackReport, endpoint: endpoint)
            do {
                try await reportClient.send(
                    event.kind,
                    snapshot: event.snapshot,
                    delegate: trace.map(KidsPerformanceTaskDelegate.init(span:))
                )
                trace?.finish()
            } catch {
                trace?.finish(error: error)
                // Error descriptions and request bodies can contain credentials.
                logger.warning("Playback report failed", metadata: ["endpoint": .string(endpoint.rawValue)])
                throw error
            }
        }
        Self.lastReporter = reporter
    }

    private func snapshot() -> PlaybackStateInfo? {
        guard let item, let manager else { return nil }
        return reportClient.identity.snapshot(
            positionTicks: manager.seconds.ticks,
            audio: item.selectedAudioStreamIndex,
            subtitle: item.selectedSubtitleStreamIndex,
            isPaused: manager.playbackRequestStatus == .paused
        )
    }

    private func reportProgress() {
        guard !ended, let reporter, let snapshot = snapshot() else { return }
        lastSnapshot = snapshot
        reporter.update(snapshot)
    }

    private func finish() {
        guard !ended else { return }
        ended = true
        if let snapshot = snapshot() ?? lastSnapshot {
            reporter?.finish(snapshot)
        }
        reporter = nil
        subscriptions.removeAll()
    }

    private func setup(with manager: MediaPlayerManager) {
        Timer.publish(every: 5, on: .main, in: .common).autoconnect()
            .sink { [weak self] _ in self?.reportProgress() }
            .store(in: &subscriptions)
        manager.$playbackRequestStatus.dropFirst()
            .sink { [weak self] status in
                // @Published emits before storage changes, so take the requested
                // status from the publisher rather than rereading the manager.
                guard let self, !self.ended, let reporter = self.reporter, var snapshot = self.snapshot() else { return }
                snapshot.isPaused = status == .paused
                self.lastSnapshot = snapshot
                reporter.update(snapshot)
            }
            .store(in: &subscriptions)
        manager.$playbackItem
            .sink { [weak self] newItem in
                guard let self else { return }
                if newItem !== self.item {
                    self.finish()
                }
            }
            .store(in: &subscriptions)
        manager.actions.sink { [weak self] action in
            switch action {
            case .stop, .error: self?.finish()
            default: break
            }
        }.store(in: &subscriptions)
        Notifications[.applicationWillTerminate].publisher
            .sink { [weak self] _ in self?.finish() }
            .store(in: &subscriptions)
    }
}
