//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import AVFoundation
import Combine
import FactoryKit
import Foundation
import JellyfinAPI
import SwiftfinAccountModels
import SwiftfinAsyncStreams
import UIKit

extension Container {
    var notificationCenter: Factory<NotificationCenter> {
        self { NotificationCenter.default }.singleton
    }
}

enum Notifications {

    typealias Keys = _AnyKey

    class _AnyKey {
        typealias Key = Notifications.Key
    }

    /// App-owned names and injected center; all custom posts are actor-bound.
    @MainActor
    class Key<Payload: Sendable>: _AnyKey {
        @Injected(\.notificationCenter)
        fileprivate var notificationCenter

        fileprivate nonisolated let event: NotificationEvent<Payload>
        nonisolated var name: Notification.Name {
            event.name
        }

        nonisolated var rawValue: String {
            event.name.rawValue
        }

        convenience init(_ string: String) {
            self.init(Notification.Name(string))
        }

        init(_ name: Notification.Name, decodeStrategy: (@Sendable ([AnyHashable: Any]) -> Payload?)? = nil) {
            event = .init(name, decode: decodeStrategy)
        }

        func post(_ payload: Payload) {
            event.post(payload, to: notificationCenter)
        }

        func post() where Payload == Void {
            event.post(to: notificationCenter)
        }

        var publisher: AnyPublisher<Payload, Never> {
            event.publisher(in: notificationCenter)
        }
    }

    /// UIKit status is read on the main actor after a value-free notification.
    @MainActor
    private final class MainActorKey<Payload: Sendable>: Key<Payload> {
        private let decodeOnMain: @MainActor @Sendable () -> Payload?
        init(_ name: Notification.Name, decode: @escaping @MainActor @Sendable () -> Payload?) {
            decodeOnMain = decode
            super.init(name)
        }

        override var publisher: AnyPublisher<Payload, Never> {
            event.mainActorPublisher(in: notificationCenter, read: decodeOnMain)
        }
    }

    @MainActor
    static subscript<Payload: Sendable>(key: Key<Payload>) -> Key<Payload> {
        key
    }
}

// MARK: - Keys

extension Notifications.Key {

    // MARK: - App Flow

    static var didPurge: Key<Void> {
        Key("didPurge")
    }

    static var didChangeServerConnection: Key<ServerConnection> {
        Key("didChangeServerConnection")
    }

    static var didSendStopReport: Key<Void> {
        Key("didSendStopReport")
    }

    static var didRequestGlobalRefresh: Key<Void> {
        Key("didRequestGlobalRefresh")
    }

    // MARK: - Media Items

    // TODO: come up with a cleaner, more defined way for item update notifications

    static var itemUserDataDidChange: Key<UserItemDataDto> {
        Key("itemUserDataDidChange")
    }

    /// - Payload: The new item with updated metadata.
    static var itemMetadataDidChange: Key<BaseItemDto> {
        Key("itemMetadataDidChange")
    }

    /// - Payload: The ID of the item that should refresh
    static var itemShouldRefreshMetadata: Key<String> {
        Key("itemShouldRefresh")
    }

    /// - Payload: The ID of the deleted item.
    static var didDeleteItem: Key<String> {
        Key("didDeleteItem")
    }

    static var recordingTimersDidChange: Key<Void> {
        Key("recordingTimersDidChange")
    }

    // MARK: - Server

    static var didConnectToServer: Key<ServerState> {
        Key("didConnectToServer")
    }

    static var didDeleteServer: Key<ServerState> {
        Key("didDeleteServer")
    }

    // MARK: - User

    /// - Payload: The ID of the user whose Profile Image changed.
    static var didChangeUserProfile: Key<String> {
        Key("didChangeUserProfile")
    }

    static var didAddServerUser: Key<UserDto> {
        Key("didAddServerUser")
    }

    // MARK: - Playback

    static var didStartPlayback: Key<Void> {
        Key("didStartPlayback")
    }

    static var interruption: Key<Void> {
        Key(AVAudioSession.interruptionNotification)
    }

    // MARK: - UIAccessibility

    static var darkerSystemColorsStatusDidChange: Key<Bool> {
        Notifications.MainActorKey(UIAccessibility.darkerSystemColorsStatusDidChangeNotification) {
            UIAccessibility.isDarkerSystemColorsEnabled
        }
    }

    // MARK: - UIApplication

    static var applicationDidEnterBackground: Key<Void> {
        Key(UIApplication.didEnterBackgroundNotification)
    }

    static var applicationWillEnterForeground: Key<Void> {
        Key(UIApplication.willEnterForegroundNotification)
    }

    static var applicationWillResignActive: Key<Void> {
        Key(UIApplication.willResignActiveNotification)
    }

    static var applicationWillTerminate: Key<Void> {
        Key(UIApplication.willTerminateNotification)
    }

    static var sceneDidEnterBackground: Key<Void> {
        Key(UIScene.didEnterBackgroundNotification)
    }

    static var sceneWillEnterForeground: Key<Void> {
        Key(UIScene.willEnterForegroundNotification)
    }

    static var avAudioSessionInterruption: Key<(AVAudioSession.InterruptionType, AVAudioSession.InterruptionOptions)> {
        Key(AVAudioSession.interruptionNotification) { userInfo in
            guard let rawValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
                  let type = AVAudioSession.InterruptionType(rawValue: rawValue)
            else {
                return nil
            }
            let options = (userInfo[AVAudioSessionInterruptionOptionKey] as? UInt)
                .map(AVAudioSession.InterruptionOptions.init(rawValue:)) ?? []

            return (type, options)
        }
    }
}
