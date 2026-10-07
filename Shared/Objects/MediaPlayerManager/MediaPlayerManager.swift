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
import KidsPlayback
import SwiftfinAsyncStreams
import SwiftfinCollections
import SwiftfinFormatting
import SwiftfinMediaTracks
import SwiftfinPlaybackPreparation
import SwiftfinText
import SwiftfinTime
import SwiftfinUIState
#if os(tvOS)
import KidsDiagnostics
#endif

// TODO: proper error catching
// TODO: be a UserSessionService?

typealias MediaPlayerManagerPublisher = LegacyEventPublisher<UIObjectEvent<MediaPlayerManager>>

extension Scope {
    static let session = Cached()
}

extension Container {

    var mediaPlayerManagerPublisher: Factory<MediaPlayerManagerPublisher> {
        self { MediaPlayerManagerPublisher() }
            .singleton
    }

    /// An obsolete player's completion must not evict a newer factory selection.
    @MainActor
    func resetMediaPlayerManager(ifCurrent manager: MediaPlayerManager) {
        guard mediaPlayerManager() === manager else { return }
        mediaPlayerManager.reset()
    }

    @MainActor
    var mediaPlayerManager: Factory<MediaPlayerManager> {
        self { @MainActor in
            .init(
                playbackItem: .init(
                    baseItem: .init(),
                    mediaSource: .init(),
                    playSessionID: "",
                    url: URL(string: "/")!,
                    deviceProfile: .init(),
                    sidecarSubtitles: []
                )
            )
        }
        .scope(.session)
    }
}

@MainActor
final class MediaPlayerManager: ViewModel {

    enum Action: Sendable {
        case ended
        case error(any Error)
        case playNewItem(provider: MediaPlayerItemProvider)
        case setBitrate(bitrate: PlaybackBitrate)
        case setRate(rate: Float)
        case setTrack(type: MediaStreamType, from: Int?, to: Int? = nil)
        case start
        case stop
        case togglePlayPause
    }

    typealias _Action = Action
    let actions = LegacyEventPublisher<Action>()
    private let preparationRequests = LatestRequest<MediaPlayerItem>()
    private let publication = AsyncOperationGate()
    @Published
    private(set) var error: (any Error)?
    @CommittedPublished
    private(set) var state: State = .initial {
        didSet { objectWillChange.send() }
    }

    enum State: Equatable, Sendable {
        case error
        case initial
        case loadingItem
        case playback
        case stopped
    }

    /// A status indicating the player's request for media playback.
    enum PlaybackRequestStatus {

        /// The player requests media playback
        case playing

        /// The player is paused
        case paused
    }

    @Published
    var playbackItem: MediaPlayerItem? = nil {
        didSet {
            if oldValue !== playbackItem {
                oldValue?.previewImageProvider?.invalidate()
            }
            if let playbackItem {
                self.item = playbackItem.baseItem
                seconds = playbackItem.baseItem.startSeconds ?? .zero
                playbackItem.manager = self
                setSupplements()

                logger.info(
                    "Playing new item",
                    metadata: [
                        "itemID": .stringConvertible(playbackItem.baseItem.id ?? "Unknown"),
                        "isTranscoding": .stringConvertible(playbackItem.mediaSource.transcodingURL != nil),
                    ]
                )

                let preview = playbackItem.previewImageProvider
                let initialSeconds = seconds
                Task { _ = await preview?.image(for: initialSeconds) }
            }
        }
    }

    @Published
    private(set) var item: BaseItemDto
    @Published
    private(set) var playbackRequestStatus: PlaybackRequestStatus = .playing
    @Published
    var rate: Float = Defaults[.VideoPlayer.Playback.playbackRate] {
        didSet {
            Defaults[.VideoPlayer.Playback.playbackRate] = rate
        }
    }

    @Published
    var queue: AnyMediaPlayerQueue? = nil

    @Published
    var supplements: [any MediaPlayerSupplement] = []

    // TODO: replace with graph dependency package
    private func setSupplements() {
        var newSupplements = Defaults[.VideoPlayer.supplements].compactMap { kind -> (any MediaPlayerSupplement)? in
            switch kind {
            case .info:
                return MediaInfoSupplement(item: item)
            case .chapters:
                guard let chapters = item.fullChapterInfo, chapters.isNotEmpty else { return nil }
                return MediaChaptersSupplement(chapters: chapters)
            case .queue:
                return queue
            case .people:
                guard let people = item.mergedPeople?.filter({ $0.type?.isSupported == true }),
                      people.isNotEmpty else { return nil }
                return MediaPeopleSupplement(people: people)
            case .playbackInformation:
                guard let itemID = item.id else { return nil }
                return PlaybackInformationSupplement(itemID: itemID)
            }
        }

        if item.isLiveStream, Defaults[.Experimental.videoPlayerEPG] {
            newSupplements.append(EPGSupplement())
        }

        self.supplements = newSupplements
    }

    /// The current seconds media playback is set to.
    let secondsBox: PublishedBox<Duration> = .init(initialValue: .zero)

    var seconds: Duration {
        get { secondsBox.value }
        set { secondsBox.value = newValue }
    }

    var playbackBitrate: PlaybackBitrate {
        playbackItem?.requestedBitrate ?? Defaults[.VideoPlayer.Playback.appMaximumBitrate]
    }

    /// Holds a weak reference to the current media player proxy.
    weak var proxy: (any MediaPlayerProxy)? {
        didSet {
            if var proxy {
                proxy.manager = self
            }
        }
    }

    /// Allows a dedicated presentation to handle authorization failures without inheriting queue navigation.
    var onPlaybackError: ((Error) -> Void)?

    private var initialMediaPlayerItemProvider: MediaPlayerItemProvider?

    // MARK: init

//    static let empty: MediaPlayerManager = .init()

//    override private init() {
//        self.item = .init()
//        self.state = .stopped
//        super.init()
//    }

    init(
        provider: MediaPlayerItemProvider,
        queue: (any MediaPlayerQueue)? = nil
    ) {
        self.item = provider.item
        self.queue = queue.map { AnyMediaPlayerQueue($0) }
        self.state = .loadingItem
        self.initialMediaPlayerItemProvider = provider
        super.init()

        self.queue?.manager = self
    }

    init(
        playbackItem: MediaPlayerItem,
        queue: (any MediaPlayerQueue)? = nil
    ) {
        self.item = playbackItem.baseItem
        self.queue = queue.map { AnyMediaPlayerQueue($0) }
        self.state = .playback
        super.init()

        self.queue?.manager = self
        self.playbackItem = playbackItem
    }

    private var acceptsCommands: Bool {
        state != .stopped && state != .error
    }

    private func handleEnd() {
        guard acceptsCommands else { return }
        actions.send(.ended)
        guard let runtime = item.runtime else { stop()
            return
        }
        guard PlaybackCompletionPolicy.acceptsEnd(position: seconds, runtime: runtime) else { return }
        guard let connection = playbackItem?.connection else { stop()
            return
        }
        do { try connection.preparation.checkBinding() }
        catch { stop()
            return
        }
        if let nextItem = queue?.nextItem,
           (try? authenticatedUser.data.configuration?.enableNextEpisodeAutoPlay) == true
        {
            playNewItem(provider: nextItem)
        } else {
            stop()
        }
    }

    func ended() {
        handleEnd()
    }

    func ended() async {
        handleEnd()
        await preparationRequests.waitUntilFinished()
    }

    private func handleError(_ error: any Error) {
        guard acceptsCommands else { return }
        publication.cancel()
        state = .error
        preparationRequests.cancel()
        self.error = error
        actions.send(.error(error))
        logger.error("Playback failed", metadata: [
            "error": .string("\((error as NSError).domain):\((error as NSError).code)"),
            "itemID": .stringConvertible(item.id ?? "Unknown")
        ])
        onPlaybackError?(error)
        proxy?.stop()
        Container.shared.mediaPlayerManagerPublisher().send(.retired(self))
        Container.shared.resetMediaPlayerManager(ifCurrent: self)
    }

    func error(_ error: any Error) {
        handleError(error)
    }

    func error(_ error: any Error) async {
        handleError(error)
    }

    private func submitItem(provider: MediaPlayerItemProvider) {
        requestItem(action: .playNewItem(provider: provider), baseItem: provider.item) { try await provider() }
    }

    func playNewItem(provider: MediaPlayerItemProvider) {
        submitItem(provider: provider)
    }

    func playNewItem(provider: MediaPlayerItemProvider) async {
        submitItem(provider: provider)
        await preparationRequests.waitUntilFinished()
    }

    private func submitBitrate(bitrate: PlaybackBitrate) {
        guard let currentItem = playbackItem else { return }
        requestRebuild(currentItem: currentItem, requestedBitrate: bitrate, action: .setBitrate(bitrate: bitrate))
    }

    func setBitrate(bitrate: PlaybackBitrate) {
        submitBitrate(bitrate: bitrate)
    }

    func setBitrate(bitrate: PlaybackBitrate) async {
        submitBitrate(bitrate: bitrate)
        await preparationRequests.waitUntilFinished()
    }

    func setPlaybackRequestStatus(status: PlaybackRequestStatus) {
        guard acceptsCommands, playbackRequestStatus != status else { return }
        playbackRequestStatus = status
        switch status {
        case .paused: proxy?.pause()
        case .playing: proxy?.play()
        }
    }

    private func updateRate(rate: Float) {
        guard acceptsCommands, !Task.isCancelled else { return }
        actions.send(.setRate(rate: rate))
        if self.rate != rate {
            self.rate = rate
        }
    }

    func setRate(rate: Float) {
        updateRate(rate: rate)
    }

    func setRate(rate: Float) async {
        updateRate(rate: rate)
    }

    private func submitTrack(type: MediaStreamType, from oldIndex: Int?, to newIndex: Int? = nil) {
        guard acceptsCommands, let currentItem = playbackItem, let connection = currentItem.connection else { return }
        do { try connection.preparation.checkBinding() }
        catch { return }
        let valid: Bool = switch type {
        case .audio: currentItem.audioStreams.contains { $0.index == oldIndex }
        case .subtitle: newIndex == -1 || currentItem.subtitleStreams.contains { $0.index == newIndex }
        default: false
        }
        guard valid else { logger.warning("Invalid playback track selection")
            return
        }
        let action = Action.setTrack(type: type, from: oldIndex, to: newIndex)
        if currentItem.isRebuildRequired(type: type, from: oldIndex, to: newIndex) {
            requestRebuild(
                currentItem: currentItem,
                audioStreamIndex: type == .audio ? newIndex : nil,
                subtitleStreamIndex: type == .subtitle ? newIndex : nil,
                action: action
            )
        } else {
            actions.send(action)
            currentItem.switchTrack(type: type, index: newIndex)
        }
    }

    func setTrack(type: MediaStreamType, from oldIndex: Int?, to newIndex: Int? = nil) {
        submitTrack(
            type: type,
            from: oldIndex,
            to: newIndex
        )
    }

    func setTrack(type: MediaStreamType, from oldIndex: Int?, to newIndex: Int? = nil) async {
        submitTrack(type: type, from: oldIndex, to: newIndex)
        await preparationRequests.waitUntilFinished()
    }

    private func submitStart() {
        guard acceptsCommands else { return }
        guard let provider = initialMediaPlayerItemProvider else { stop()
            return
        }
        initialMediaPlayerItemProvider = nil
        requestItem(action: .start, baseItem: provider.item) { try await provider() }
    }

    func start() {
        submitStart()
    }

    func start() async {
        submitStart()
        await preparationRequests.waitUntilFinished()
    }

    private func retire() {
        guard state != .stopped else { return }
        publication.cancel()
        state = .stopped
        preparationRequests.cancel()
        playbackItem?.previewImageProvider?.invalidate()
        actions.send(.stop)
        proxy?.stop()
        Container.shared.mediaPlayerManagerPublisher().send(.retired(self))
        Container.shared.resetMediaPlayerManager(ifCurrent: self)
    }

    func stop() {
        retire()
    }

    func stop() async {
        retire()
    }

    private func toggleTransport() {
        guard acceptsCommands else { return }
        actions.send(.togglePlayPause)
        setPlaybackRequestStatus(status: playbackRequestStatus == .playing ? .paused : .playing)
    }

    func togglePlayPause() {
        toggleTransport()
    }

    func togglePlayPause() async {
        toggleTransport()
    }

    private func requestItem(
        action: Action,
        baseItem: BaseItemDto,
        position: Duration? = nil,
        operation: @escaping @MainActor @Sendable () async throws -> MediaPlayerItem
    ) {
        guard acceptsCommands, !Task.isCancelled else { return }
        let validate = publication.begin()
        preparationRequests.replace(operation: {
            try validate()
            let prepared = try await operation()
            try validate()
            return prepared
        }, begin: { [weak self] in
            guard let self else { return }
            do {
                try validate()
                self.state = .loadingItem
                try validate()
                self.item = baseItem
                try validate()
                self.setSupplements()
                try validate()
                self.proxy?.stop()
                try validate()
                self.actions.send(action)
            } catch {}
        }, failure: { [weak self] failure in
            self?.error(failure)
        }, receive: { [weak self] prepared in
            guard let self else { return }
            do {
                try validate()
                try self.installPlaybackItem(prepared)
                try validate()
                if let position {
                    self.seconds = position
                    try validate()
                }
                self.state = .playback
            } catch is CancellationError {}
            catch { self.error(error) }
        })
    }

    /// Rebuilds the playback item with new stream indexes / bitrate.
    /// Stops the current proxy, requests new playback info from the server, and starts playback with the new configuration.
    ///
    /// Rebuilds the current item
    private func requestRebuild(
        currentItem: MediaPlayerItem,
        audioStreamIndex: Int? = nil,
        subtitleStreamIndex: Int? = nil,
        requestedBitrate: PlaybackBitrate? = nil,
        action: Action
    ) {
        guard acceptsCommands, let connection = currentItem.connection else { return }
        do { try connection.preparation.checkBinding() }
        catch { return }
        let currentSeconds = seconds
        currentItem.previewImageProvider?.invalidate()
        requestItem(action: action, baseItem: currentItem.baseItem, position: currentSeconds) {
            try await MediaPlayerItem.build(
                for: currentItem.baseItem,
                connection: connection,
                mediaSource: currentItem.mediaSource,
                audioStreamIndex: audioStreamIndex ?? currentItem.selectedAudioStreamIndex,
                subtitleStreamIndex: subtitleStreamIndex ?? currentItem.selectedSubtitleStreamIndex,
                videoPlayerType: currentItem.videoPlayerType,
                requestedBitrate: requestedBitrate ?? currentItem.requestedBitrate,
                modifyItem: { item in
                    if item.userData == nil {
                        item.userData = UserItemDataDto(key: "")
                    }
                    item.userData?.playbackPositionTicks = currentSeconds.ticks
                }
            )
        }
    }

    /// Final synchronous publication check after any awaited provider/rebuild.
    /// The accountless factory placeholder never enters this path.
    private func installPlaybackItem(_ prepared: MediaPlayerItem) throws {
        try Task.checkCancellation()
        guard state != .stopped, state != .error, let connection = prepared.connection else { throw CancellationError() }
        try connection.preparation.checkBinding()
        playbackItem = prepared
    }

    static func getMaxBitrate(
        for requestedBitrate: PlaybackBitrate,
        testSize: PlaybackBitrateTestSize = Defaults[.VideoPlayer.appMaximumBitrateTest],
        preparation: PlaybackPreparationClient? = nil
    ) async throws -> Int {

        guard requestedBitrate == .auto else { return requestedBitrate.rawValue }

        let client: PlaybackPreparationClient
        if let preparation {
            client = preparation
        } else {
            guard let session = Container.shared.currentUserSession() else { throw UserSessionError.missingCurrentSession }
            client = session.playbackPreparation
        }
        try client.checkBinding()
        let testStartTime = ContinuousClock.now
        #if os(tvOS)
        let transfer = KidsPerformance.begin(.http, endpoint: .bitrate, values: ["bytes": Double(testSize.rawValue)])
        defer { transfer?.finish(Task.isCancelled ? .cancelled : .failure) }
        let bytes = try await client.bitrateBytes(
            size: testSize.rawValue,
            delegate: transfer.map(KidsPerformanceTaskDelegate.init(span:))
        )
        transfer?.finish(values: ["bytes": Double(bytes.count)])
        #else
        let bytes = try await client.bitrateBytes(size: testSize.rawValue)
        #endif
        try Task.checkCancellation()
        return try PlaybackBitrateMeasurement.estimate(
            bytes: bytes.count,
            elapsed: testStartTime.duration(to: .now)
        )
    }
}
