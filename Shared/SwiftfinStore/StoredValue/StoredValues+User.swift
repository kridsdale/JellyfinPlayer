//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Defaults
import FactoryKit
import Foundation
import JellyfinAPI
import SwiftfinStoredValues

// TODO: also have matching properties on `UserState` that get/set values
// TODO: cleanup/organize

// MARK: keys

@MainActor
extension StoredValues.Keys {

    /// Construct a key where `ownerID` is the id of the user in the
    /// current user session, or always returns the default if there
    /// isn't a current session user.
    @MainActor
    static func CurrentUserKey<Value: Storable>(
        _ name: String? = nil,
        field: String,
        default defaultValue: Value,
        storage: StoredValues.Key<Value>.StorageDestination = .sql,
    ) -> Key<Value> {
        guard let currentUser = Container.shared.currentUserSession()?.user else {
            return Key(always: defaultValue)
        }

        return Key(
            name ?? field,
            ownerID: currentUser.id,
            field: field,
            storage: storage,
            default: defaultValue
        )
    }

    static func UserKey<Value: Storable>(
        _ name: String? = nil,
        ownerID: String,
        field: String,
        default defaultValue: Value
    ) -> Key<Value> {
        Key(
            name ?? field,
            ownerID: ownerID,
            field: field,
            default: defaultValue
        )
    }

    static func UserKey<Value: Storable>(always: Value) -> Key<Value> {
        Key(always: always)
    }
}

// MARK: values

extension LocalUserAccessPolicy: Storable {}
extension UserDto: @retroactive Defaults.Serializable {}
extension UserDto: @retroactive Storable {}

@MainActor
extension StoredValues.Keys {

    @MainActor
    enum User {

        static var users: Key<[UserState]> {
            Key(
                "users",
                ownerID: "swiftfinApp",
                field: "users",
                storage: .sql,
                default: []
            )
        }

        // Doesn't use `CurrentUserKey` because data may be
        // retrieved and stored without a user session
        static func accessPolicy(id: String) -> Key<LocalUserAccessPolicy> {
            UserKey(
                ownerID: id,
                field: "accessPolicy",
                default: .none
            )
        }

        // Doesn't use `CurrentUserKey` because data may be
        // retrieved and stored without a user session
        static func data(id: String) -> Key<UserDto> {
            UserKey(
                ownerID: id,
                field: "userData",
                default: .init()
            )
        }

        @MainActor
        static var accessPolicy: Key<LocalUserAccessPolicy> {
            CurrentUserKey(
                field: "currentUserAccessPolicy",
                default: .none
            )
        }

        @MainActor
        static func libraryStyle(id: String?) -> Key<LibraryStyle> {
            CurrentUserKey(
                id,
                field: "setting-libraryStyle",
                default: .default
            )
        }

        // TODO: for now, only used for `sortBy` and `sortOrder`. Need to come up with
        //       rules for how stored filters work with libraries that should init
        //       with non-default filters (atow ex: favorites)
        @MainActor
        static func libraryFilters(parentID: String?) -> Key<ItemFilterCollection> {
            CurrentUserKey(
                parentID,
                field: "setting-libraryFilters",
                default: ItemFilterCollection.default
            )
        }

        static func pinHint(id: String) -> Key<String> {
            UserKey(
                ownerID: id,
                field: "pinHint",
                default: ""
            )
        }

        @MainActor
        static var customDeviceProfiles: Key<[CustomDeviceProfile]> {
            CurrentUserKey(
                field: "customDeviceProfiles",
                default: []
            )
        }

        @MainActor
        static var enabledTrailers: Key<TrailerSelection> {
            CurrentUserKey(
                field: "enabledTrailers",
                default: .all
            )
        }

        @MainActor
        static var itemViewAttributes: Key<[ItemViewAttribute]> {
            CurrentUserKey(
                field: "itemViewAttributes",
                default: ItemViewAttribute.allCases
            )
        }

        @MainActor
        static var previewImageScrubbing: Key<PreviewImageScrubbingOption> {
            CurrentUserKey(
                field: "previewImageScrubbing",
                default: .trickplay(fallbackToChapters: false)
            )
        }

        @MainActor
        static var forceDVTranscode: Key<Bool> {
            CurrentUserKey(
                field: "forceDVTranscode",
                default: false
            )
        }

        @MainActor
        static var forceHDRTranscode: Key<Bool> {
            CurrentUserKey(
                field: "forceHDRTranscode",
                default: false
            )
        }

        @MainActor
        static var forceSubtitleBurnIn: Key<Bool> {
            CurrentUserKey(
                field: "forceSubtitleBurnIn",
                default: false
            )
        }
    }
}
