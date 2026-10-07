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
import JellyfinAPI
import SwiftfinAsyncStreams
import SwiftfinCollections
import SwiftfinFormatting
import SwiftfinLocalization
import SwiftfinMediaTracks
import SwiftfinNetworking
import SwiftfinServerOperations
import SwiftfinText
import SwiftUI

// TODO: have proxies be a `PlaybackInformationProvider`
//       - be labeled pair information
// TODO: tvOS: use material background

class PlaybackInformationSupplement: ObservableObject, @MainActor MediaPlayerSupplement {

    let displayTitle: String = L10n.session
    let itemID: String
    let presentationStyle: MediaPlayerSupplementPresentationStyle = .expanded
    let provider: PlaybackInformationProvider

    var id: String {
        "PlaybackInformation-\(itemID)"
    }

    init(itemID: String) {
        self.itemID = itemID
        self.provider = .init(itemID: itemID)
    }

    var videoPlayerBody: some PlatformView {
        OverlayView(viewModel: provider)
    }
}

extension PlaybackInformationSupplement {

    private struct OverlayView: PlatformView {

        @Environment(\.safeAreaInsets)
        private var safeAreaInsets: EdgeInsets

        @EnvironmentObject
        private var containerState: VideoPlayerContainerState
        @EnvironmentObject
        private var manager: MediaPlayerManager

        @ObservedObject
        var viewModel: PlaybackInformationProvider

        private var mediaSource: MediaSourceInfo? {
            manager.playbackItem?.mediaSource
        }

        private var videoStream: MediaStream? {
            manager.playbackItem?.videoStreams.first
        }

        private var audioStream: MediaStream? {
            guard let playbackItem = manager.playbackItem else { return nil }
            if let selectedIndex = playbackItem.selectedAudioStreamIndex {
                return playbackItem.audioStreams.first { $0.index == selectedIndex }
            }
            return playbackItem.audioStreams.first
        }

        @ViewBuilder
        private var playbackInfoSection: some View {
            Text(L10n.mediaPlayback)
                .font(.subheadline)
                .fontWeight(.semibold)
                .padding(.vertical, 4)

            LabeledContent(L10n.videoPlayer, value: Defaults[.VideoPlayer.videoPlayerType].displayTitle)

            if let playMethod = viewModel.currentSession?.playMethodDisplayTitle {
                LabeledContent(L10n.method, value: playMethod)
            }

            if let deliveryProtocol = mediaSource?.protocol {
                LabeledContent(L10n.source, value: deliveryProtocol.rawValue.uppercased())
            }

            if let transcodingSubProtocol = mediaSource?.transcodingSubProtocol {
                LabeledContent(L10n.protocol, value: transcodingSubProtocol.rawValue.uppercased())
            }
        }

        @ViewBuilder
        private var videoInfoSection: some View {
            if videoStream != nil || (manager.proxy as? any VideoMediaPlayerProxy) != nil {
                Text(L10n.video)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .padding(.vertical, 4)

                if let width = videoStream?.width, let height = videoStream?.height {
                    LabeledContent(L10n.videoResolution, value: height.description.multiply(by: width.description))
                }

                if let proxy = manager.proxy as? any VideoMediaPlayerProxy {
                    LabeledContent(L10n.droppedFrames, value: proxy.droppedFrames.value.description)
                    LabeledContent(L10n.corruptedFrames, value: proxy.corruptedFrames.value.description)
                }
            }
        }

        @ViewBuilder
        private var streamingInfoSection: some View {
            if let transcodingInfo = viewModel.currentSession?.transcodingInfo {
                Text(viewModel.currentSession?.playMethodDisplayTitle.map { L10n.streamInfoWithMethod($0) } ?? L10n.streamInfo)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .padding(.vertical, 4)

                if let videoCodec = transcodingInfo.videoCodec {
                    LabeledContent(
                        L10n.videoCodec,
                        value: transcodingInfo.isVideoDirect == true
                            ? "\(videoCodec.uppercased()) (\(L10n.direct))"
                            : videoCodec.uppercased()
                    )
                }

                if let audioCodec = transcodingInfo.audioCodec {
                    LabeledContent(
                        L10n.audioCodec,
                        value: transcodingInfo.isAudioDirect == true
                            ? "\(audioCodec.uppercased()) (\(L10n.direct))"
                            : audioCodec.uppercased()
                    )
                }

                if let hwAccel = transcodingInfo.hardwareAccelerationType {
                    LabeledContent(L10n.hardwareAcceleration, value: hwAccel.rawValue)
                }

                if let rawCompletion = transcodingInfo.completionPercentage,
                   let completion = Int(exactly: rawCompletion.rounded(.towardZero))
                {
                    LabeledContent(L10n.transcodeProgress, value: "\(completion)%")
                }
            }
        }

        @ViewBuilder
        private var originalMediaInfoSection: some View {
            if mediaSource != nil || videoStream != nil || audioStream != nil {
                Text(L10n.originalMediaInfo)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .padding(.vertical, 4)

                if let container = mediaSource?.container {
                    LabeledContent(L10n.container, value: container)
                }

                if let size = mediaSource?.size {
                    LabeledContent(L10n.size, value: Int64(size).formatted(.byteCount(style: .file)))
                }

                if let bitrate = mediaSource?.bitrate {
                    LabeledContent(L10n.bitrate, value: bitrate.formatted(.bitRate))
                }

                if let codec = videoStream?.codec {
                    let display = videoStream?.profile.map { "\(codec.uppercased()) \($0)" } ?? codec.uppercased()
                    LabeledContent(L10n.videoCodec, value: display)
                }

                if let bitRate = videoStream?.bitRate {
                    LabeledContent(L10n.videoBitRate, value: bitRate.formatted(.bitRate))
                }

                if let videoRangeType = videoStream?.videoRangeType {
                    LabeledContent(L10n.videoRangeType, value: videoRangeType.rawValue)
                }

                if let codec = audioStream?.codec {
                    LabeledContent(L10n.audioCodec, value: codec.uppercased())
                }

                if let bitRate = audioStream?.bitRate {
                    LabeledContent(L10n.audioBitrate, value: bitRate.formatted(.bitRate))
                }

                if let channels = audioStream?.channels {
                    LabeledContent(L10n.channels, value: "\(channels)")
                }

                if let sampleRate = audioStream?.sampleRate {
                    LabeledContent(L10n.audioSampleRate, value: "\(sampleRate) Hz")
                }
            }
        }

        @ViewBuilder
        private var transcodeReasonsSection: some View {
            if let transcodeReasons = viewModel.currentSession?.transcodingInfo?.transcodeReasons, transcodeReasons.isNotEmpty {
                Text(L10n.transcodeReasons)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .padding(.vertical, 4)

                ForEach(transcodeReasons, id: \.self) { reason in
                    Text(reason.displayTitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }

        var iOSView: some View {
            CompactOrRegularView(
                isCompact: containerState.isCompact
            ) {
                compactView
            } regularView: {
                regularView
            }
            .labeledContentStyle(.playbackInfo)
            .padding(.leading, safeAreaInsets.leading)
            .padding(.trailing, safeAreaInsets.trailing)
            .padding(.bottom, safeAreaInsets.bottom)
        }

        @ViewBuilder
        private var compactView: some View {
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    playbackInfoSection
                    videoInfoSection
                    originalMediaInfoSection
                    streamingInfoSection
                    transcodeReasonsSection
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .scrollIndicators(.hidden)
            .edgePadding()
        }

        @ViewBuilder
        private var regularView: some View {
            ScrollView {
                HStack(alignment: .top, spacing: 24) {
                    VStack(alignment: .leading, spacing: 4) {
                        playbackInfoSection
                        videoInfoSection
                        streamingInfoSection
                        transcodeReasonsSection
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)

                    VStack(alignment: .leading, spacing: 4) {
                        originalMediaInfoSection
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }
            }
            .scrollIndicators(.hidden)
            .edgePadding()
        }

        var tvOSView: some View {
            regularView
                .labeledContentStyle(.playbackInfo)
                .focusSection()
        }
    }
}

/// App-only composition receipt: no session/client globals enter the policy library.
private struct PlaybackSessionSnapshot: Sendable {
    let sessions: [SessionInfoDto]
    let binding: UserSession?
    let transport: JellyfinTransport?
    let deviceID: String?

    @MainActor
    func isCurrent(in manager: UserSessionManager) -> Bool {
        guard let binding, let transport else { return manager.currentSession == nil }
        return manager.currentSession === binding && binding.client === transport
    }
}

class PlaybackInformationProvider: ViewModel, MediaPlayerObserver {

    @Published
    var currentSession: SessionInfoDto? = nil

    weak var manager: MediaPlayerManager?
    private let sessionRequests = LatestRequest<SessionInfoDto?>()

    init(itemID: String) {
        super.init()
        let sessionManager = Container.shared.userSessionManager()
        Publishers.Merge(
            sessionManager.$currentSession.map { _ in () },
            Notifications[.didChangeServerConnection].publisher.map { _ in () }
        )
        .map { [weak sessionManager] _ -> AnyPublisher<PlaybackSessionSnapshot, Never> in
            guard let session = sessionManager?.currentSession else {
                return Just(PlaybackSessionSnapshot(sessions: [], binding: nil, transport: nil, deviceID: nil))
                    .eraseToAnyPublisher()
            }
            let transport = session.client
            let deviceID = transport.configuration.deviceID
            return session.serverSocketManager.sessions()
                .map { PlaybackSessionSnapshot(sessions: $0, binding: session, transport: transport, deviceID: deviceID) }
                .prepend(PlaybackSessionSnapshot(sessions: [], binding: session, transport: transport, deviceID: deviceID))
                .eraseToAnyPublisher()
        }
        .switchToLatest()
        .receive(on: DispatchQueue.main)
        .sink { [weak self, weak sessionManager] snapshot in
            guard let self else { return }
            self.sessionRequests.replace(operation: { [weak sessionManager] in
                guard let sessionManager, snapshot.isCurrent(in: sessionManager) else { throw CancellationError() }
                return ServerOperationsPolicy.playbackSession(in: snapshot.sessions, deviceID: snapshot.deviceID, itemID: itemID)
            }, receive: { [weak self, weak sessionManager] session in
                guard let sessionManager, snapshot.isCurrent(in: sessionManager) else { return }
                self?.currentSession = session
            })
        }
        .store(in: &cancellables)
    }
}
