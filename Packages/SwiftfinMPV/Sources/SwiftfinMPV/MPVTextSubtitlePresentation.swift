//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation
import MPVUI
import Observation

/// Latest semantic-caption value; reader ownership and cleanup remain on the UI actor.
@MainActor
@Observable
public final class MPVTextSubtitlePresentation {
    public private(set) var snapshot = TextSubtitleSnapshot()
    @ObservationIgnored
    private var observationID: UUID?
    @ObservationIgnored
    private var reader: Task<Void, Never>?
    public init() {}

    public func observe(_ controller: MPVPlaybackController, generation: UUID, load: @MainActor () -> Void) async {
        guard !Task.isCancelled else { return }
        clear()
        let id = UUID()
        observationID = id
        let stream = controller.subtitles(generation: generation)
        let task = Task { @MainActor [weak self, weak controller] in
            for await snapshot in stream {
                guard !Task.isCancelled, let self, self.observationID == id,
                      controller?.isCurrent(generation) == true else { return }
                self.snapshot = snapshot
            }
        }
        reader = task
        load()
        defer {
            if observationID == id {
                clear()
            }
        }
        await withTaskCancellationHandler { await task.value } onCancel: { task.cancel() }
    }

    public func clear() {
        observationID = nil
        reader?.cancel()
        reader = nil
        snapshot = TextSubtitleSnapshot()
    }

    isolated deinit { reader?.cancel() }
}
