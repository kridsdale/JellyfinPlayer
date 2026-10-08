//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import FactoryKit
import JellyfinAPI
import SwiftfinLocalization
import SwiftfinPlaybackPreparation
import SwiftfinUserAdministration
import SwiftUI

// TODO: static width for tvOS

extension VideoPlayer.PlaybackControls.Toolbar.ActionButtons {

    struct AutoPlay: View {

        @ViewContextContains(.isInMenu)
        private var isInMenu

        @EnvironmentObject
        private var manager: MediaPlayerManager

        @State
        private var userConfiguration: UserConfiguration?
        @State
        private var updateConnection: PlaybackConnection?
        @State
        private var updates: UserConfigurationUpdates?

        @Toaster
        private var toaster

        private var isAutoPlayEnabled: Bool {
            guard let connection = manager.playbackItem?.connection,
                  (try? connection.preparation.checkBinding()) != nil else { return false }
            let current = Container.shared.currentUserSession()?.user.data.configuration
            // Reuse optimistic presentation only while its account snapshot is current.
            if updateConnection === connection, let userConfiguration, userConfiguration == current {
                return userConfiguration.enableNextEpisodeAutoPlay == true
            }
            return current?.enableNextEpisodeAutoPlay == true
        }

        private var systemImage: String {
            if isAutoPlayEnabled {
                VideoPlayerActionButton.autoPlay.systemImage
            } else {
                VideoPlayerActionButton.autoPlay.secondarySystemImage
            }
        }

        @MainActor
        private func toggleAutoPlay() {
            guard manager.queue != nil,
                  let connection = manager.playbackItem?.connection else { return }
            do {
                try connection.preparation.checkBinding()
                guard let session = Container.shared.currentUserSession() else { throw CancellationError() }
                let validate: UserConfigurationUpdates.Checkpoint = { [weak manager, weak session, weak connection] in
                    guard let manager, let session, let connection,
                          Container.shared.currentUserSession() === session,
                          manager.playbackItem?.connection === connection,
                          manager.queue != nil,
                          manager.state != .stopped, manager.state != .error else { throw CancellationError() }
                    try connection.preparation.checkBinding()
                }
                try validate()
                if updateConnection !== connection || updates == nil {
                    updates?.cancel()
                    updates = session.userConfigurationUpdates
                    updateConnection = connection
                }
                guard let updates else { throw CancellationError() }
                let configuration = session.user.data.configuration ?? UserConfiguration()
                let enabled = try updates.toggle(
                    from: configuration,
                    validate: validate,
                    willSubmit: { updated in
                        userConfiguration = updated
                        session.user.data.configuration = updated
                    },
                    failure: { [weak toaster] _ in
                        toaster?.present(L10n.unknownError, systemName: "exclamationmark.triangle")
                    }
                )
                try validate()
                toaster.present(
                    enabled ? "Auto Play on" : "Auto Play off",
                    systemName: enabled ? "play.circle.fill" : "stop.circle"
                )
            } catch is CancellationError {
                // Retired playback/account intent has no new presentation effect.
            } catch {
                toaster.present(L10n.unknownError, systemName: "exclamationmark.triangle")
            }
        }

        var body: some View {
            Button {
                toggleAutoPlay()
            } label: {
                Label(
                    L10n.autoPlay,
                    systemImage: systemImage
                )

                if isInMenu {
                    Text(isAutoPlayEnabled ? "On" : "Off")
                }
            }
            .videoPlayerActionButtonTransition()
            .if(!UIDevice.isTV) { button in
                button.id(isAutoPlayEnabled)
            }
            .disabled(manager.queue == nil)
            // Admitted saves belong to UserSession, not the transient menu/button.
        }
    }
}
