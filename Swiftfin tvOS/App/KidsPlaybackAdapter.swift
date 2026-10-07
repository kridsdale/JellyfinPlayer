//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Combine
import Foundation
import Get
import JellyfinAPI
import KidsCatalog
import KidsDiagnostics
import KidsDomain
import KidsExperience
import KidsPlaybackSession
import SwiftUI

@MainActor
final class SwiftfinKidsPlaybackFactory: KidsPlaybackSessionFactory {
    private let sessions: UserSessionManager
    init(sessions: UserSessionManager) {
        self.sessions = sessions
    }

    func prepare(
        item: KidsItem,
        title: KidsItem,
        mode: KidsPlaybackMode,
        position: Double,
        episodes: [KidsItem],
        delegate: any KidsPlaybackSessionDelegate,
        performance: KidsPerformanceSpan?, simulateStreamFailure: Bool
    ) async throws -> KidsPlaybackController {
        guard let session = sessions.currentSession else { throw KidsAPIError.authentication }
        let identity = (
            server: session.server.id,
            user: session.user.id,
            url: session.server.effectiveServerURL,
            token: session.user.accessToken
        )
        let metadata = KidsPerformance.begin(.metadata, endpoint: .itemDetails)
        defer { metadata?.finish(Task.isCancelled ? .cancelled : .failure) }
        let preparation = session.playbackPreparation
        let raw = try await preparation.item(
            id: item.id,
            delegate: metadata.map(KidsPerformanceTaskDelegate.init(span:))
        )
        metadata?.finish()
        guard raw.id == item.id, raw.mediaType == .video,
              (item.kind == .episode && raw.type == .episode) || (item.kind == .movie && raw.type == .movie)
        else { throw KidsContractError.denied }
        let start = max(0, position)
        #if DEBUG
        let failStreamOnce = simulateStreamFailure
        #endif
        let provider = MediaPlayerItemProvider(item: raw) { base, _ in
            guard let current = self.sessions.currentSession,
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
                    return MediaPlayerItem(
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
        let driver = SwiftfinKidsPlaybackDriver(manager: manager, performance: performance)
        return KidsPlaybackController(
            item: item,
            title: title,
            mode: mode,
            position: start,
            episodes: episodes,
            driver: driver,
            delegate: delegate,
            performance: performance
        )
    }
}

@MainActor
final class SwiftfinKidsPlaybackDriver: KidsPlaybackDriver {
    let manager: MediaPlayerManager
    let proxy = VLCMediaPlayerProxy()
    private let subject = PassthroughSubject<KidsPlaybackDriverEvent, Never>()
    private var observations = Set<AnyCancellable>()
    private var stopped = false

    init(manager: MediaPlayerManager, performance: KidsPerformanceSpan?) {
        self.manager = manager
        manager.proxy = proxy
        proxy.performance = performance
        manager.$state.sink { [weak self] _ in self?.subject.send(.updated) }.store(in: &observations)
        manager.$playbackRequestStatus.dropFirst().sink { [weak self] status in
            guard let self else { return }
            self.subject.send(.transport(paused: status == .paused, seconds: self.manager.seconds.seconds, terminal: self.frame.terminal))
        }.store(in: &observations)
        manager.onPlaybackError = { [weak self] error in
            let failure: KidsPlaybackFailure = if case let Get.APIError.unacceptableStatusCode(status) = error,
                                                  status == 401 || status == 403
            {
                .authentication
            } else {
                .stream
            }
            self?.subject.send(.failure(failure))
        }
        proxy.onNaturalEnd = { [weak self] in self?.subject.send(.naturalEnd) }
    }

    var events: AnyPublisher<KidsPlaybackDriverEvent, Never> {
        subject.eraseToAnyPublisher()
    }

    var frame: KidsPlaybackFrame {
        let native = proxy.native.frame
        let state = native.state
        var value = KidsPlaybackFrame()
        value.seconds = native.time.seconds
        value.paused = state == .paused
        value.playing = state == .playing
        value.buffering = proxy.isBuffering.value
        value.preparing = manager.state == .loadingItem
        value.applyingStartPosition = proxy.isApplyingStartPosition
        value.failed = manager.state == .error
        value.terminal = state == .stopped || state == .idle || state == .stopping
        value.reachedEnd = native.reachedEnd
        value.displayedPictures = Int(clamping: native.displayedPictures)
        value.seekable = native.seekable
        return value
    }

    func start() {
        proxy.native.updates.sink { [weak self] in
            guard let self, !self.stopped else { return }
            self.subject.send(.updated)
        }.store(in: &observations)
        manager.start()
    }

    func beginReporting() {
        for observer in manager.playbackItem?.observers ?? [] {
            (observer as? KidsMediaProgressObserver)?.beginPlayback()
        }
    }

    func togglePlayPause() {
        manager.togglePlayPause()
    }

    func pause() {
        proxy.pause()
    }

    func seek(seconds: Double) {
        proxy.setSeconds(.seconds(seconds))
    }

    func stop() async {
        guard !stopped else { return }
        stopped = true
        proxy.pause()
        await manager.stop()
        proxy.manager = nil
        observations.removeAll()
    }
}

/// The host owns native view state; the session library has no SwiftUI or SDK dependency.
struct SwiftfinKidsPlaybackSurface: View {
    let session: KidsPlaybackController
    @StateObject
    private var containerState = VideoPlayerContainerState()
    var body: some View {
        if let driver = session.driver as? SwiftfinKidsPlaybackDriver {
            driver.proxy.videoPlayerBody.environmentObject(driver.manager).environmentObject(containerState)
        }
    }
}

/// Native track values remain inside the host; the parent gate authorizes every mutation.
struct SwiftfinKidsTrackControls: View {
    let session: KidsPlaybackController
    let authorize: @MainActor () -> Bool
    var body: some View {
        if let driver = session.driver as? SwiftfinKidsPlaybackDriver, let playback = driver.manager.playbackItem {
            Picker("Audio", selection: Binding(get: { playback.selectedAudioStreamIndex ?? 0 }, set: { guard authorize() else { return }
                playback.selectedAudioStreamIndex = $0
            })) {
                ForEach(playback.audioStreams, id: \.index) { stream in
                    Text(stream.displayTitle ?? stream.language ?? "Audio").tag(stream.index ?? 0)
                }
            }
            Picker(
                "Captions",
                selection: Binding(get: { playback.selectedSubtitleStreamIndex ?? -1 }, set: { guard authorize() else { return }
                    playback.selectedSubtitleStreamIndex = $0
                })
            ) {
                Text("Off").tag(-1)
                ForEach(playback.subtitleStreams, id: \.index) { stream in
                    Text(stream.displayTitle ?? stream.language ?? "Captions").tag(stream.index ?? -1)
                }
            }
        }
    }
}

@MainActor
final class SwiftfinKidsPlaybackPresentation: KidsPlaybackPresentation {
    func surface(for session: KidsPlaybackController) -> AnyView {
        AnyView(SwiftfinKidsPlaybackSurface(session: session))
    }

    func tracks(for session: KidsPlaybackController, authorize: @escaping @MainActor () -> Bool) -> AnyView {
        AnyView(SwiftfinKidsTrackControls(session: session, authorize: authorize))
    }
}
