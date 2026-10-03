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
        model: KidsAppModel
    ) async throws -> KidsPlaybackController {
        guard let session = Container.shared.currentUserSession() else { throw KidsAPIError.authentication }
        let raw = try await session.client.send(Paths.getItem(itemID: item.id, userID: session.user.id)).value
        guard raw.id == item.id, raw.mediaType == .video,
              (item.kind == .episode && raw.type == .episode) || (item.kind == .movie && raw.type == .movie)
        else { throw KidsContractError.denied }
        let start = max(0, position)
        let provider = MediaPlayerItemProvider(item: raw) { base, _ in
            try await MediaPlayerItem.build(for: base, videoPlayerType: .vlc, modifyItem: { dto in
                if dto.userData == nil {
                    dto.userData = UserItemDataDto(key: "")
                }
                dto.userData?.playbackPositionTicks = Int(start * 10_000_000)
            })
        }
        let manager = MediaPlayerManager(provider: provider, queue: nil)
        return KidsPlaybackController(item: item, title: title, mode: mode, episodes: episodes, manager: manager, model: model)
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
        let time = manager.seconds.seconds
        if time.isFinite {
            seconds = max(0, time)
        }
        paused = proxy.player.state == .paused
        let playing = proxy.player.state == .playing
        buffering = proxy.isBuffering.value || manager.state == .loadingItem
        if playing && !began {
            began = true
            model?.playbackBegan(self)
        }
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
