//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

#if canImport(UIKit)
import Combine
import Foundation
import UIKit

@MainActor
public final class EPGScrollProxy: ObservableObject {

    public init() {}

    private weak var contentScrollView: UIScrollView?

    private var didCenter = false
    private var isConnected = true
    private var observationGeneration = UUID()
    private var isSyncingHorizontally = false
    private var isSyncingVertically = false

    private let horizontalScrollViews = NSHashTable<UIScrollView>.weakObjects()
    private let verticalScrollViews = NSHashTable<UIScrollView>.weakObjects()

    private let horizontalObservations = NSMapTable<UIScrollView, NSKeyValueObservation>(
        keyOptions: .weakMemory,
        valueOptions: .strongMemory
    )
    private let verticalObservations = NSMapTable<UIScrollView, NSKeyValueObservation>(
        keyOptions: .weakMemory,
        valueOptions: .strongMemory
    )

    public func registerContent(_ scrollView: UIScrollView, centeringOn target: CGFloat?) {
        if contentScrollView !== scrollView {
            didCenter = false
        }

        contentScrollView = scrollView

        registerHorizontal(scrollView)

        if !didCenter, let target, let offset = offset(centering: target) {
            scrollView.setContentOffset(
                CGPoint(x: offset, y: scrollView.contentOffset.y),
                animated: false
            )
            didCenter = true
        }
    }

    public func registerHorizontal(_ scrollView: UIScrollView) {
        horizontalScrollViews.add(scrollView)

        guard isConnected, horizontalObservations.object(forKey: scrollView) == nil else { return }

        let generation = observationGeneration
        let receive: @MainActor @Sendable () -> Void = { [weak self, weak scrollView] in
            guard let self, let scrollView, self.isConnected,
                  self.observationGeneration == generation,
                  self.horizontalObservations.object(forKey: scrollView) != nil else { return }
            self.horizontalOffsetDidChange(scrollView)
        }
        let observation = scrollView.observe(\.contentOffset) { _, _ in
            if Thread.isMainThread {
                // Preserve synchronous recursion guards for normal UIKit scroll delivery.
                MainActor.assumeIsolated { receive() }
            } else {
                Task { @MainActor in receive() }
            }
        }

        horizontalObservations.setObject(observation, forKey: scrollView)
    }

    public func registerVertical(_ scrollView: UIScrollView) {
        verticalScrollViews.add(scrollView)

        guard isConnected, verticalObservations.object(forKey: scrollView) == nil else { return }

        let generation = observationGeneration
        let receive: @MainActor @Sendable () -> Void = { [weak self, weak scrollView] in
            guard let self, let scrollView, self.isConnected,
                  self.observationGeneration == generation,
                  self.verticalObservations.object(forKey: scrollView) != nil else { return }
            self.verticalOffsetDidChange(scrollView)
        }
        let observation = scrollView.observe(\.contentOffset) { _, _ in
            if Thread.isMainThread {
                // Preserve synchronous recursion guards for normal UIKit scroll delivery.
                MainActor.assumeIsolated { receive() }
            } else {
                Task { @MainActor in receive() }
            }
        }

        verticalObservations.setObject(observation, forKey: scrollView)
    }

    public func reset() {
        didCenter = false

        guard let contentScrollView else { return }

        contentScrollView.setContentOffset(
            CGPoint(x: 0, y: contentScrollView.contentOffset.y),
            animated: false
        )
    }

    public func connect() {
        isConnected = true

        horizontalScrollViews.allObjects.forEach(registerHorizontal)
        verticalScrollViews.allObjects.forEach(registerVertical)
    }

    public func disconnect() {
        isConnected = false
        observationGeneration = UUID()

        invalidateObservations(in: horizontalObservations)
        invalidateObservations(in: verticalObservations)
    }

    public func scrollTo(centering target: CGFloat) {
        guard let contentScrollView, let offset = offset(centering: target) else { return }

        contentScrollView.setContentOffset(
            CGPoint(x: offset, y: contentScrollView.contentOffset.y),
            animated: true
        )
    }

    private func offset(centering target: CGFloat) -> CGFloat? {
        guard let contentScrollView else { return nil }

        return ScrollCentering.offset(
            target: target,
            viewport: contentScrollView.bounds.width,
            content: contentScrollView.contentSize.width
        )
    }

    private func invalidateObservations(
        in observations: NSMapTable<UIScrollView, NSKeyValueObservation>
    ) {
        let observationTokens = observations.objectEnumerator()?.allObjects as? [NSKeyValueObservation] ?? []
        observationTokens.forEach { $0.invalidate() }
        observations.removeAllObjects()
    }

    private func horizontalOffsetDidChange(_ source: UIScrollView) {
        guard !isSyncingHorizontally else { return }

        isSyncingHorizontally = true
        defer { isSyncingHorizontally = false }

        let generation = observationGeneration
        let scrollViews = horizontalObservations.keyEnumerator().allObjects as? [UIScrollView] ?? []

        for scrollView in scrollViews {
            // A delegate callback can disconnect or replace these observations.
            guard isConnected, observationGeneration == generation else { return }
            guard scrollView !== source,
                  abs(scrollView.contentOffset.x - source.contentOffset.x) > 0.5
            else { continue }

            scrollView.setContentOffset(
                CGPoint(x: source.contentOffset.x, y: scrollView.contentOffset.y),
                animated: false
            )
        }
    }

    private func verticalOffsetDidChange(_ source: UIScrollView) {
        guard !isSyncingVertically else { return }

        isSyncingVertically = true
        defer { isSyncingVertically = false }

        let generation = observationGeneration
        let scrollViews = verticalObservations.keyEnumerator().allObjects as? [UIScrollView] ?? []

        for scrollView in scrollViews {
            // A delegate callback can disconnect or replace these observations.
            guard isConnected, observationGeneration == generation else { return }
            guard scrollView !== source,
                  abs(scrollView.contentOffset.y - source.contentOffset.y) > 0.5
            else { continue }

            scrollView.setContentOffset(
                CGPoint(x: scrollView.contentOffset.x, y: source.contentOffset.y),
                animated: false
            )
        }
    }
}

#endif
