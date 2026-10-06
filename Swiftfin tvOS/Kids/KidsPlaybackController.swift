//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

// SPDX-License-Identifier: MPL-2.0
import AVFoundation
import Combine
import FactoryKit
import Foundation
import Get
import JellyfinAPI
import KidsCore
import SwiftUI

@MainActor
final class KidsPlaybackController: ObservableObject, Identifiable {
    let id = UUID()
    let item: KidsItem
    let title: KidsItem
    let mode: KidsPlaybackMode
    let episodes: [KidsItem]
    let manager: MediaPlayerManager
    var performance: KidsPerformanceSpan?
    lazy var proxy = VLCMediaPlayerProxy()
    @Published
    var controlsVisible = false
    @Published
    var paused = false
    @Published
    var seconds = 0.0
    @Published
    var buffering = true
    @Published
    var recovery = false
    @Published
    var showCountdown = false
    @Published
    var countdown = 10
    @Published
    var nextEpisode: KidsItem?
    @Published
    var failed = false
    @Published
    var tracksPresented = false
    private weak var model: KidsAppModel?
    private var began = false
    private var finished = false
    var allowsCheckpoints = true
    private var stopped = false
    private var tickTask: Task<Void, Never>?
    private var eventTask: Task<Void, Never>?
    private var requestedStartPosition = 0.0
    private var waitingSince: Date?
    private var lastCheckpoint = Date.distantPast
    private var lastControl = Date.now
    private var observers = Set<AnyCancellable>()

    private init(
        item: KidsItem,
        title: KidsItem,
        mode: KidsPlaybackMode,
        episodes: [KidsItem],
        manager: MediaPlayerManager,
        model: KidsAppModel
    ) {
        self.item = item
        self.title = title
        self.mode = mode
        self.episodes = episodes
        self.manager = manager
        self.model = model
        if !model.isPreview {
            manager.proxy = proxy
        }
        manager.$state.sink { [weak self] state in
            if state == .error {
                self?.failed = true
                self?.recovery = true
                self?.proxy.pause()
            }
        }.store(in: &observers)
        if !model.isPreview {
            // System transport commands can reach NowPlayableObserver instead of the SwiftUI handler.
            // Keep the kids controls visible for either route, while the VLC clock remains authoritative.
            manager.$playbackRequestStatus.dropFirst().sink { [weak self] status in
                guard let self, self.began, !self.stopped else { return }
                self.reveal()
                if status == .paused {
                    let clock = self.manager.seconds.seconds
                    let playerState = self.proxy.player.state
                    if clock.isFinite && playerState != .stopped && playerState != .idle && playerState != .stopping {
                        self.seconds = max(0, clock)
                    }
                    self.model?.playbackCheckpoint(self, seconds: self.seconds)
                }
            }.store(in: &observers)
            manager.onPlaybackError = { [weak self] error in
                guard let self, let model = self.model, model.activePlayback === self else { return }
                if case let Get.APIError.unacceptableStatusCode(status) = error, status == 401 || status == 403 {
                    model.show(KidsAPIError.authentication)
                    return
                }
                // VLC can collapse HTTP failures into a generic stream error. Check access once, without retry loops.
                Task { [weak self] in
                    guard let self, let api = model.api, let binding = model.binding else { return }
                    do { try await api.validate(binding) }
                    catch {
                        guard model.activePlayback === self, model.binding == binding else { return }
                        if let failure = error as? KidsAPIError, [.authentication, .policy, .libraryChanged].contains(failure) {
                            model.show(failure)
                        }
                    }
                }
            }
            proxy.onNaturalEnd = { [weak self] in
                guard let self, self.began, !self.finished, !self.stopped else { return }
                self.finished = true
                Task { await self.model?.completed(self) }
            }
        }
    }

    static func prepare(
        item: KidsItem,
        title: KidsItem,
        mode: KidsPlaybackMode,
        position: Double,
        episodes: [KidsItem],
        model: KidsAppModel,
        performance: KidsPerformanceSpan? = nil
    ) async throws -> KidsPlaybackController {
        guard let session = Container.shared.currentUserSession() else { throw KidsAPIError.authentication }
        let identity = (
            server: session.server.id,
            user: session.user.id,
            url: session.server.effectiveServerURL,
            token: session.user.accessToken
        )
        let metadata = KidsPerformance.begin(.metadata, endpoint: .itemDetails)
        defer { metadata?.finish(Task.isCancelled ? .cancelled : .failure) }
        let raw = try await session.client.send(
            Paths.getItem(itemID: item.id, userID: session.user.id),
            delegate: metadata.map(KidsPerformanceTaskDelegate.init(span:))
        ).value
        metadata?.finish()
        guard raw.id == item.id, raw.mediaType == .video,
              (item.kind == .episode && raw.type == .episode) || (item.kind == .movie && raw.type == .movie)
        else { throw KidsContractError.denied }
        let start = max(0, position)
        #if DEBUG
        let failStreamOnce = model.consumeValidationStreamFailure()
        #endif
        let provider = MediaPlayerItemProvider(item: raw) { base, _ in
            guard let current = Container.shared.currentUserSession(),
                  current.server.id == identity.server, current.user.id == identity.user,
                  current.server.effectiveServerURL == identity.url,
                  current.user.accessToken == identity.token else { throw KidsAPIError.authentication }
            try Task.checkCancellation()
            return try await KidsPerformance.$current.withValue(performance) {
                let build = KidsPerformance.begin(.provider)
                defer { build?.finish(Task.isCancelled ? .cancelled : .failure) }
                let built = try await MediaPlayerItem.build(for: base, preparedItem: raw, videoPlayerType: .vlc, modifyItem: { dto in
                    if dto.userData == nil {
                        dto.userData = UserItemDataDto(key: "")
                    }
                    dto.userData?.playbackPositionTicks = Int(start * 10_000_000)
                })
                build?.finish()
                #if DEBUG
                // A one-shot real connection refusal exercises VLC recovery without interrupting the household server.
                if failStreamOnce {
                    return await MediaPlayerItem(
                        baseItem: built.baseItem,
                        mediaSource: built.mediaSource,
                        playSessionID: built.playSessionID,
                        url: URL(string: "http://127.0.0.1:9")!,
                        requestedBitrate: built.requestedBitrate,
                        deviceProfile: built.deviceProfile,
                        initialAudioStreamIndex: built.selectedAudioStreamIndex,
                        initialSubtitleStreamIndex: built.selectedSubtitleStreamIndex,
                        previewImageProvider: built.previewImageProvider,
                        thumbnailProvider: built.thumbnailProvider
                    )
                }
                #endif
                let video = built.mediaSource.mediaStreams?.first { $0.type == .video }
                performance?.mark(.providerReady, values: [
                    "transcoding": built.mediaSource.transcodingURL == nil ? 0 : 1,
                    "video_codec": Double(KidsPerformanceCodec(video?.codec).rawValue),
                    "width": Double(video?.width ?? 0), "height": Double(video?.height ?? 0),
                    "bit_depth": Double(video?.bitDepth ?? 0),
                    "video_fps": Double(video?.averageFrameRate ?? 0),
                    "video_bitrate": Double(video?.bitRate ?? 0)
                ])
                return built
            }
        }
        let manager = MediaPlayerManager(provider: provider, queue: nil)
        let controller = KidsPlaybackController(item: item, title: title, mode: mode, episodes: episodes, manager: manager, model: model)
        // Until native output proves an advancing clock, preserve the durable
        // requested position for failed-open Retry and its recovery timeline.
        controller.seconds = start
        controller.requestedStartPosition = start
        controller.performance = performance
        controller.proxy.performance = performance
        return controller
    }

    #if DEBUG
    static func preview(model: KidsAppModel, scenario: String) -> KidsPlaybackController {
        let movie = scenario == "movie-paused"
        let title = model.catalog[movie ? .movies : .shows]![0]
        let episodes = movie ? [] : KidsPreviewFixtures.episodes(showID: title.id)
        let item = movie ? title : episodes[0]
        let raw = BaseItemDto(id: item.id, name: "Synthetic video")
        let provider = MediaPlayerItemProvider(item: raw) { _, _ in throw KidsAPIError.unavailable }
        let controller = KidsPlaybackController(
            item: item,
            title: title,
            mode: movie ? .movie : .ordered,
            episodes: episodes,
            manager: MediaPlayerManager(provider: provider),
            model: model
        )
        controller.buffering = false
        controller.paused = scenario == "paused" || movie
        controller.seconds = movie ? 1200 : 120
        controller.began = movie // Exercise the real stop checkpoint before a parent-authorized restart.
        controller.controlsVisible = scenario == "paused" || scenario == "controls" || movie
        controller.recovery = scenario == "reconnecting"
        controller.showCountdown = scenario == "countdown"
        controller.nextEpisode = movie ? nil : episodes[1]
        return controller
    }
    #endif

    func start() {
        performance?.mark(.managerStart)
        if model?.isPreview != true {
            // Register before the media can open. Each subscription is independent;
            // this does not consume the bridge used by SwiftVLC or the view.
            let events = proxy.player.events(policy: .newest(64), filter: { event in
                switch event {
                case .stateChanged, .timeChanged, .voutChanged, .bufferingProgress: true
                default: false
                }
            })
            eventTask = Task { [weak self] in
                for await _ in events {
                    guard !Task.isCancelled else { return }
                    // Let SwiftVLC's own main-actor event mirror update first.
                    await Task.yield()
                    guard let self, !self.stopped else { return }
                    self.updatePlaybackState()
                }
            }
        }
        manager.start()
        tickTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self else { return }
                await self.tick()
            }
        }
    }

    private func tick() async {
        if showCountdown {
            countdown -= 1
            if countdown <= 0 {
                tickTask?.cancel()
                await model?.continuePlayback(self)
            }
            return
        }
        guard !stopped else { return }
        updatePlaybackState() // Recovery fallback if event delivery was interrupted.
        if began && !finished && Date.now.timeIntervalSince(lastCheckpoint) >= 10 {
            model?.playbackCheckpoint(self, seconds: seconds)
            lastCheckpoint = .now
        }
        if buffering {
            if waitingSince == nil {
                waitingSince = .now
            }
            if Date.now.timeIntervalSince(waitingSince!) >= 15 {
                recovery = true
                proxy.pause()
            }
        } else {
            waitingSince = nil
        }
        if !paused && !recovery && Date.now.timeIntervalSince(lastControl) > 5 {
            controlsVisible = false
        }
    }

    private func updatePlaybackState() {
        guard !stopped, model?.isPreview != true else { return }
        let playerState = proxy.player.state
        let terminal = playerState == .stopped || playerState == .idle || playerState == .stopping
        let time = proxy.player.currentTime.seconds
        // Do not publish a stale pre-seek clock or overwrite a durable checkpoint
        // when VLC resets its clock after a stop.
        if time.isFinite, !proxy.isApplyingStartPosition, !(terminal && began),
           began || time >= requestedStartPosition
        {
            let currentSeconds = max(0, time)
            if seconds != currentSeconds {
                seconds = currentSeconds
            }
        }
        let currentlyPaused = playerState == .paused
        if paused != currentlyPaused {
            paused = currentlyPaused
        }
        if !began, KidsPlaybackReadiness.permitsPresentation(
            playingOrPaused: playerState == .playing || paused,
            buffering: proxy.isBuffering.value,
            preparing: manager.state == .loadingItem,
            resumePending: proxy.isApplyingStartPosition,
            failedOrRecovering: failed || recovery || manager.state == .error,
            requestedPosition: requestedStartPosition,
            clock: time,
            displayedPictures: Int(clamping: proxy.player.statistics?.displayedPictures ?? 0)
        ) {
            performance?.once(.firstClock, values: ["seconds": time])
            performance?.mark(.playbackBegan)
            began = true
            for observer in manager.playbackItem?.observers ?? [] {
                (observer as? KidsMediaProgressObserver)?.beginPlayback()
            }
            model?.playbackBegan(self)
        }
        let currentlyBuffering = proxy.isBuffering.value || manager.state == .loadingItem || (!began && !recovery) ||
            (terminal && began && !finished && !proxy.player.didReachEnd)
        if buffering != currentlyBuffering {
            buffering = currentlyBuffering
        }
    }

    func toggle() {
        guard !stopped else { return }
        if model?.isPreview == true {
            paused.toggle()
        } else {
            manager.togglePlayPause()
        }
        controlsVisible = true
        lastControl = .now
        model?.playbackCheckpoint(self, seconds: seconds)
    }

    func reveal() {
        controlsVisible = true
        lastControl = .now
    }

    func seek(_ delta: Double) {
        guard !stopped, paused, delta.isFinite else { return }
        guard model?.isPreview == true || proxy.player.isSeekable else { return }
        let runtime = item.runtime ?? 0
        let target = max(0, min(runtime > 0 ? runtime : .greatestFiniteMagnitude, seconds + delta))
        if model?.isPreview != true {
            proxy.setSeconds(.seconds(target))
        }
        seconds = target
        reveal()
        model?.playbackCheckpoint(self, seconds: target)
    }

    func retry() async {
        guard let model else { return }
        let saved = began ? seconds : requestedStartPosition
        model.playbackCheckpoint(self, seconds: saved)
        await stop()
        model.activePlayback = nil
        model.play(title, mode: mode, retryItem: item, retryPosition: saved, continuing: true)
    }

    func stop() async {
        if !stopped {
            if began && !finished {
                model?.playbackCheckpoint(self, seconds: seconds)
            }
            stopped = true
            eventTask?.cancel()
            eventTask = nil
            if model?.isPreview != true {
                proxy.pause()
                await manager.stop()
            }
            // Break observer retain cycles and release the stream after its stop report is sent.
            if model?.isPreview != true {
                proxy.manager = nil
            }
        }
        if !showCountdown {
            tickTask?.cancel()
        }
    }

    func pauseOnBackground() {
        guard !stopped else { return }
        if model?.isPreview == true {
            paused = true
        } else {
            proxy.pause()
        }
        model?.playbackCheckpoint(self, seconds: seconds)
    }

    func handleBack() async {
        if controlsVisible && !recovery && !showCountdown {
            controlsVisible = false
        } else {
            await model?.stopPlayback()
        }
    }

    deinit {
        tickTask?.cancel()
        eventTask?.cancel()
    }
}
