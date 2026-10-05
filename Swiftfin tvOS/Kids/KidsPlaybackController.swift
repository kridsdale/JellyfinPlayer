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
            try await KidsPerformance.$current.withValue(performance) {
                let build = KidsPerformance.begin(.provider)
                defer { build?.finish(Task.isCancelled ? .cancelled : .failure) }
                let built = try await MediaPlayerItem.build(for: base, videoPlayerType: .vlc, modifyItem: { dto in
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
        let playerState = proxy.player.state
        let terminal = playerState == .stopped || playerState == .idle || playerState == .stopping
        let time = manager.seconds.seconds
        // libVLC resets its clock after an unexpected stop. Keep the last valid resume position.
        if time.isFinite && !(terminal && began) {
            seconds = max(0, time)
        }
        paused = playerState == .paused
        let playing = playerState == .playing
        if playing && !began {
            performance?.mark(.playbackBegan)
            began = true
            model?.playbackBegan(self)
        }
        // Some failed HTTP opens stop without a VLC error notification. A prepared item is not a playing stream.
        buffering = proxy.isBuffering.value || manager.state == .loadingItem || (!began && !recovery) ||
            (terminal && began && !finished && !proxy.player.didReachEnd)
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
        let saved = seconds
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
    }
}
