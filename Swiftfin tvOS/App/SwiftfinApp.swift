//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import KidsDiagnostics
import SwiftUI

@main
struct SwiftfinApp: App {

    @UIApplicationDelegateAdaptor(KidsCloudAppDelegate.self)
    private var cloudDelegate

    init() {
        _ = KidsPerformance.launch
        Self.configure()

        UINavigationBar.appearance().titleTextAttributes = [.foregroundColor: UIColor.label]
    }

    var body: some Scene {
        WindowGroup {
            OverlayToastView {
                WithLocalUserAuthentication {
                    RootView()
                }
            }
        }
    }
}

/// Silent CloudKit pushes are handled by the SDK's persistent-store mirroring.
final class KidsCloudAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        if (Bundle.main.object(forInfoDictionaryKey: "KidsCloudSyncEnabled") as? String) == "YES" {
            application.registerForRemoteNotifications()
        }
        return true
    }
}
