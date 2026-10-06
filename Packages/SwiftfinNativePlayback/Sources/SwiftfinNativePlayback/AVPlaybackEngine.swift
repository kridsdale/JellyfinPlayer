//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import AVFoundation
import AVKit
import Foundation
import SwiftUI

@MainActor
final class AVPlaybackEngine: NativePlaybackEngine {
    let player = AVPlayer()
    private var statusObserver: NSKeyValueObservation?
    private var controlObserver: NSKeyValueObservation?
    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?
    private var generation: UUID?
    private var receive: (@MainActor (NativeObservation, UUID) -> Void)?
    private var rate: Float = 1
    private var fills = false
    #if os(iOS) || os(tvOS)
    private let layers = NSHashTable<AVPlayerLayer>.weakObjects()
    private let controls = NSHashTable<AVPlayerViewController>.weakObjects()
    #endif

    isolated deinit { stop() }

    func open(
        _ request: NativePlaybackRequest,
        generation: UUID,
        receive: @escaping @MainActor (NativeObservation, UUID) -> Void
    ) {
        stop()
        self.generation = generation
        self.receive = receive
        let item = AVPlayerItem(url: request.url)
        #if os(iOS) || os(tvOS)
        item.externalMetadata = Self.metadata(request)
        #endif
        player.replaceCurrentItem(with: item)
        statusObserver = item.observe(\.status, options: [.new, .initial]) { @Sendable [weak self] _, value in
            guard let raw = value.newValue?.rawValue else { return }
            Task { @MainActor [weak self] in
                guard let self, self.generation == generation else { return }
                switch AVPlayerItem.Status(rawValue: raw) {
                case .readyToPlay: self.emit(.ready, generation: generation)
                case .failed: self.emit(.failed, generation: generation)
                default: break
                }
            }
        }
        controlObserver = player.observe(\.timeControlStatus, options: [.new]) { @Sendable [weak self] player, _ in
            let raw = player.timeControlStatus.rawValue
            Task { @MainActor [weak self] in
                guard let self, self.generation == generation else { return }
                guard self.player.timeControlStatus.rawValue == raw else { return }
                let state: NativePlaybackState = switch AVPlayer.TimeControlStatus(rawValue: raw) {
                case .playing: .playing
                case .waitingToPlayAtSpecifiedRate: .waiting
                default: .paused
                }
                self.emit(.state(state), generation: generation)
            }
        }
        timeObserver = player
            .addPeriodicTimeObserver(
                forInterval: CMTime(seconds: 1, preferredTimescale: 1000),
                queue: .main
            ) { @Sendable [weak self] time in
                let seconds = time.seconds
                guard seconds.isFinite, seconds >= 0 else { return }
                Task { @MainActor [weak self] in
                    self?.emit(.clock(.seconds(seconds)), generation: generation)
                }
            }
        endObserver = NotificationCenter.default.addObserver(
            forName: AVPlayerItem.didPlayToEndTimeNotification,
            object: item,
            queue: .main
        ) { @Sendable [weak self] _ in
            Task { @MainActor [weak self] in self?.emit(.ended, generation: generation) }
        }
    }

    private func emit(_ observation: NativeObservation, generation: UUID) {
        guard self.generation == generation else { return }
        receive?(observation, generation)
    }

    func seek(_ time: Duration, completion: @escaping @MainActor (Bool) -> Void) {
        let seconds = Double(time.components.seconds) + Double(time.components.attoseconds) / 1e18
        guard seconds.isFinite else { completion(false)
            return
        }
        player
            .seek(
                to: CMTime(seconds: max(0, seconds), preferredTimescale: 1000),
                toleranceBefore: .zero,
                toleranceAfter: .zero
            ) { @Sendable finished in
                Task { @MainActor in completion(finished) }
            }
    }

    var time: Duration {
        let seconds = player.currentTime().seconds
        return seconds.isFinite && seconds >= 0 ? .seconds(seconds) : .zero
    }

    func play() {
        player.playImmediately(atRate: rate)
    }

    func pause() {
        player.pause()
    }

    func stop() {
        generation = nil
        receive = nil
        player.pause()
        if let timeObserver {
            player.removeTimeObserver(timeObserver)
        }
        timeObserver = nil
        statusObserver?.invalidate()
        statusObserver = nil
        controlObserver?.invalidate()
        controlObserver = nil
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
        }
        endObserver = nil
        player.replaceCurrentItem(with: nil)
    }

    func rate(_ value: Float) {
        rate = value
        if player.rate != 0 {
            player.rate = value
        }
    }

    func aspectFill(_ value: Bool) {
        fills = value
        #if os(iOS) || os(tvOS)
        for layer in layers.allObjects {
            layer.videoGravity = value ? .resizeAspectFill : .resizeAspect
        }
        for view in controls.allObjects {
            view.videoGravity = value ? .resizeAspectFill : .resizeAspect
        }
        #endif
    }

    func surface(showControls: Bool) -> AnyView {
        #if os(iOS) || os(tvOS)
        if showControls {
            return AnyView(NativeControlSurface(engine: self))
        }
        return AnyView(NativeLayerSurface(engine: self))
        #else
        return AnyView(VideoPlayer(player: player))
        #endif
    }

    static func metadata(_ request: NativePlaybackRequest) -> [AVMetadataItem] {
        let values: [(AVMetadataIdentifier, String?)] = [
            (.commonIdentifierTitle, request.title),
            (.iTunesMetadataTrackSubTitle, request.subtitle),
            (.commonIdentifierDescription, request.overview),
        ]
        return values.map { identifier, value in
            let item = AVMutableMetadataItem()
            item.identifier = identifier
            item.value = value as? NSCopying & NSObjectProtocol
            item.extendedLanguageTag = "und"
            return item.copy() as! AVMetadataItem
        }
    }

    #if os(iOS) || os(tvOS)
    private struct NativeControlSurface: UIViewControllerRepresentable {
        let engine: AVPlaybackEngine
        func makeUIViewController(context _: Context) -> AVPlayerViewController {
            let view = AVPlayerViewController()
            view.player = engine.player
            engine.controls.add(view)
            view.videoGravity = engine.fills ? .resizeAspectFill : .resizeAspect
            engine.player.allowsExternalPlayback = true
            engine.player.appliesMediaSelectionCriteriaAutomatically = false
            engine.player.usesExternalPlaybackWhileExternalScreenIsActive = true
            view.allowsPictureInPicturePlayback = true
            #if os(iOS)
            view.updatesNowPlayingInfoCenter = false
            #endif
            return view
        }

        func updateUIViewController(_ view: AVPlayerViewController, context _: Context) {
            view.videoGravity = engine.fills ? .resizeAspectFill : .resizeAspect
        }
    }

    private struct NativeLayerSurface: UIViewRepresentable {
        let engine: AVPlaybackEngine
        func makeUIView(context _: Context) -> LayerView {
            let view = LayerView(player: engine.player)
            engine.layers.add(view.playerLayer)
            return view
        }

        func updateUIView(_ view: LayerView, context _: Context) {
            view.playerLayer.videoGravity = engine.fills ? .resizeAspectFill : .resizeAspect
        }
    }

    private final class LayerView: UIView {
        override class var layerClass: AnyClass {
            AVPlayerLayer.self
        }

        var playerLayer: AVPlayerLayer {
            layer as! AVPlayerLayer
        }

        init(player: AVPlayer) {
            super.init(frame: .zero)
            playerLayer.player = player
        }

        @available(*, unavailable)
        required init?(coder _: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }
    }
    #endif
}
