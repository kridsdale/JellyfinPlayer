//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

// SPDX-License-Identifier: MPL-2.0
import KidsDiagnostics
import SwiftUI
import UIKit

/// A main-run-loop frame boundary after the measured view has joined a window.
/// This is a presentation opportunity, not a GPU fence or photon-level measurement.
public struct KidsPresentationProbe: UIViewRepresentable {
    private let span: KidsPerformanceSpan
    private let phase: KidsPerformancePhase
    public init(span: KidsPerformanceSpan, phase: KidsPerformancePhase) {
        self.span = span
        self.phase = phase
    }

    public func makeUIView(context: Context) -> UIView {
        ProbeView(span: span, phase: phase)
    }

    public func updateUIView(_ uiView: UIView, context: Context) {}
    public static func dismantleUIView(_ uiView: UIView, coordinator: ()) {
        guard let probe = uiView as? ProbeView else { return }
        probe.link?.invalidate()
        probe.link = nil
    }

    private final class ProbeView: UIView {
        let span: KidsPerformanceSpan
        let phase: KidsPerformancePhase
        var link: CADisplayLink?
        init(span: KidsPerformanceSpan, phase: KidsPerformancePhase) {
            self.span = span
            self.phase = phase
            super.init(frame: .zero)
            isUserInteractionEnabled = false
            isAccessibilityElement = false
            backgroundColor = .clear
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) is unsupported")
        }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            guard window != nil, link == nil else { return }
            let link = CADisplayLink(target: self, selector: #selector(frameBoundary))
            self.link = link
            link.add(to: .main, forMode: .common)
        }

        @objc
        private func frameBoundary() {
            span.once(phase)
            link?.invalidate()
            link = nil
        }
    }
}
