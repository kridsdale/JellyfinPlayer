//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

// SPDX-License-Identifier: MPL-2.0
import Foundation
import SwiftUI
import SwiftVLC

#if canImport(UIKit)
import UIKit

/// Hosts the SDK view independently of decoded readiness. The acknowledgement
/// follows actual window attachment and native layout, rather than SwiftUI task
/// scheduling or an allocated renderer alone.
@MainActor
struct VLCMountedVideoView: UIViewControllerRepresentable {
    let player: Player
    let controller: VLCPlaybackController
    let generation: UUID

    func makeUIViewController(context: Context) -> VLCVideoMountController {
        VLCVideoMountController(player: player, controller: controller, generation: generation)
    }

    func updateUIViewController(_ viewController: VLCVideoMountController, context: Context) {
        viewController.acknowledgeLayout()
    }

    static func dismantleUIViewController(_ viewController: VLCVideoMountController, coordinator: ()) {
        viewController.retire()
    }
}

@MainActor
final class VLCVideoMountController: UIViewController {
    private let hosting: UIHostingController<VideoView>
    private weak var playback: VLCPlaybackController?
    private let generation: UUID
    private let surfaceID = UUID()
    private var retired = false

    init(player: Player, controller: VLCPlaybackController, generation: UUID) {
        hosting = UIHostingController(rootView: VideoView(player))
        playback = controller
        self.generation = generation
        super.init(nibName: nil, bundle: nil)
        controller.surfaceAttached(generation: generation, id: surfaceID)
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        addChild(hosting)
        hosting.view.backgroundColor = .black
        hosting.view.frame = view.bounds
        hosting.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(hosting.view)
        hosting.didMove(toParent: self)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        acknowledgeLayout()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        acknowledgeLayout()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        playback?.surfaceUnavailable(generation: generation, id: surfaceID)
    }

    func acknowledgeLayout() {
        guard !retired else { return }
        guard isViewLoaded, view.window != nil,
              view.bounds.width > 0, view.bounds.height > 0
        else {
            playback?.surfaceUnavailable(generation: generation, id: surfaceID)
            return
        }
        hosting.view.frame = view.bounds
        hosting.view.layoutIfNeeded()
        guard hosting.view.window != nil,
              hosting.view.bounds.width > 0, hosting.view.bounds.height > 0 else { return }
        playback?.surfaceLaidOut(generation: generation, id: surfaceID, size: hosting.view.bounds.size)
    }

    func retire() {
        guard !retired else { return }
        retired = true
        playback?.surfaceDetached(generation: generation, id: surfaceID)
    }
}

#elseif canImport(AppKit)
import AppKit

@MainActor
struct VLCMountedVideoView: NSViewRepresentable {
    let player: Player
    let controller: VLCPlaybackController
    let generation: UUID

    func makeNSView(context: Context) -> VLCVideoMountView {
        VLCVideoMountView(player: player, controller: controller, generation: generation)
    }

    func updateNSView(_ view: VLCVideoMountView, context: Context) {
        view.acknowledgeLayout()
    }

    static func dismantleNSView(_ view: VLCVideoMountView, coordinator: ()) {
        view.retire()
    }
}

@MainActor
final class VLCVideoMountView: NSView {
    private let hosting: NSHostingView<VideoView>
    private weak var playback: VLCPlaybackController?
    private let generation: UUID
    private let surfaceID = UUID()
    private var retired = false

    init(player: Player, controller: VLCPlaybackController, generation: UUID) {
        hosting = NSHostingView(rootView: VideoView(player))
        playback = controller
        self.generation = generation
        super.init(frame: .zero)
        addSubview(hosting)
        hosting.autoresizingMask = [.width, .height]
        controller.surfaceAttached(generation: generation, id: surfaceID)
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func layout() {
        super.layout()
        acknowledgeLayout()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        acknowledgeLayout()
    }

    func acknowledgeLayout() {
        guard !retired else { return }
        guard window != nil, bounds.width > 0, bounds.height > 0 else {
            playback?.surfaceUnavailable(generation: generation, id: surfaceID)
            return
        }
        hosting.frame = bounds
        hosting.layoutSubtreeIfNeeded()
        guard hosting.window != nil, hosting.bounds.width > 0, hosting.bounds.height > 0 else { return }
        playback?.surfaceLaidOut(generation: generation, id: surfaceID, size: hosting.bounds.size)
    }

    func retire() {
        guard !retired else { return }
        retired = true
        playback?.surfaceDetached(generation: generation, id: surfaceID)
    }
}
#endif
