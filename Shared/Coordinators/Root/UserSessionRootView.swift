//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Defaults
import FactoryKit
import SwiftUI
#if os(tvOS)
import KidsApplication
import KidsExperience
#endif

struct UserSessionRootView: View {

    @Environment(\.localUserAuthenticationAction)
    private var authenticationAction

    @InjectedObject(\.userSessionManager)
    private var userSessionManager

    var body: some View {
        #if os(tvOS)
        #if DEBUG
        if let argument = ProcessInfo.processInfo.arguments.first(where: { $0.hasPrefix("--kids-preview=") }) {
            KidsRootView(previewScenario: String(argument.dropFirst("--kids-preview=".count)))
        } else {
            KidsRootView(model: KidsAppModel(
                accounts: SwiftfinKidsAccountHost(sessions: userSessionManager),
                playbackFactory: SwiftfinKidsPlaybackFactory(sessions: userSessionManager)
            ), playbackPresentation: SwiftfinKidsPlaybackPresentation())
                .task { await userSessionManager.start() }
        }
        #else
        KidsRootView(model: KidsAppModel(
            accounts: SwiftfinKidsAccountHost(sessions: userSessionManager),
            playbackFactory: SwiftfinKidsPlaybackFactory(sessions: userSessionManager)
        ), playbackPresentation: SwiftfinKidsPlaybackPresentation())
            .task { await userSessionManager.start() }
        #endif
        #else
        ZStack {
            switch userSessionManager.state {
            case .initial:
                ProgressView()
            case .signedOut:
                NavigationInjectionView(coordinator: .init()) {
                    SelectUserView()
                }
            case .signedIn:
                PosterPreferencesEnvironment {
                    MainTabView()
                }
                .id(userSessionManager.currentSession?.sessionIdentity)
            }
        }
        .animation(.linear(duration: 0.1), value: userSessionManager.state)
        .task {
            await userSessionManager.start()
        }
        .onOpenURL { url in
            guard let authenticationAction else { return }

            userSessionManager.handleOpenURL(url, authenticationAction: authenticationAction)
        }
        #endif
    }
}

private struct PosterPreferencesEnvironment<Content: View>: View {

    @Default(.Customization.Poster.configuration)
    private var posterConfiguration

    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .environment(\.posterConfiguration, posterConfiguration)
    }
}
