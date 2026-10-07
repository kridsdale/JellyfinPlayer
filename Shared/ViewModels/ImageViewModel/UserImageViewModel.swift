//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import CasePaths
import Foundation
import JellyfinAPI
import Nuke
import StatefulMacros
import SwiftfinImages
import SwiftfinText
import SwiftfinUserAdministration
import UIKit

@MainActor
@Stateful
final class UserImageViewModel: ViewModel {

    @CasePathable
    enum Action {
        case delete
        case upload(UIImage)

        var transition: Transition {
            switch self {
            case .delete:
                .background(.deleting)
            case .upload:
                .background(.updating)
            }
        }
    }

    enum BackgroundState {
        case deleting
        case updating
    }

    enum Event {
        case deleted
        case updated
    }

    enum State {
        case initial
        case error
    }

    @Published
    var user: UserDto

    init(user: UserDto) {
        self.user = user
        super.init()
    }

    @Function(\Action.Cases.upload)
    private func _upload(_ image: UIImage) async throws {
        guard let userID = user.id else { return }
        let client = try requireUserAdministration()
        let (imageData, contentType) = try image.data()
        try await client.uploadImage(userID: userID, data: imageData, contentType: contentType)
        try await cleanImageCache(using: client, userID: userID)
        events.send(.updated)
    }

    @Function(\Action.Cases.delete)
    private func _delete() async throws {
        guard let userID = user.id else { return }
        let client = try requireUserAdministration()
        try await client.deleteImage(userID: userID)
        try await cleanImageCache(using: client, userID: userID)
        events.send(.deleted)
    }

    private func cleanImageCache(using client: UserAdministrationClient, userID: String) async throws {
        try client.checkBinding()
        let session = try requireUserSession()
        let transport = session.client
        let selectedUser = user
        guard selectedUser.id == userID else { throw CancellationError() }

        for width: CGFloat in [60, 120, 150] {
            if let url = selectedUser.profileImageSource(client: transport, maxWidth: width).url {
                await ImagePipeline.Swiftfin.local.removeItem(for: url)
                await ImagePipeline.Swiftfin.posters.removeItem(for: url)
            }
        }

        try client.checkBinding()
        guard user.id == userID else { throw CancellationError() }
        Notifications[.didChangeUserProfile].post(userID)
    }
}
