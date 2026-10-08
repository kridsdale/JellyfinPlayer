//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Combine
import FactoryKit
import Foundation
import JellyfinAPI
import SwiftfinAsyncStreams
import SwiftfinUIState
import SwiftfinUserAdministration

/// Platform presentation for one immutable account/selected-user editor.
@MainActor
final class ServerUserAdminViewModel: ViewModel, Identifiable {
    enum BackgroundState: Hashable, Sendable { case updating, refreshing }
    struct Activity: Equatable, Sendable {
        var states: Set<BackgroundState> = []
        func `is`(_ state: BackgroundState) -> Bool {
            states.contains(state)
        }
    }

    enum Event { case updated }
    enum State: Equatable, Sendable { case initial, content, error }

    @CommittedPublished
    private(set) var user: UserDto {
        didSet { objectWillChange.send() }
    }

    @CommittedPublished
    var libraries: [BaseItemDto] = [] {
        didSet { objectWillChange.send() }
    }

    @CommittedPublished
    var background = Activity() {
        didSet { objectWillChange.send() }
    }

    @CommittedPublished
    private(set) var state: State = .initial {
        didSet { objectWillChange.send() }
    }

    @Published
    var error: (any Error)?

    @CommittedPublished
    private(set) var configurationUpdating = false {
        didSet { objectWillChange.send() }
    }

    let events = PassthroughSubject<Event, Never>()

    private weak var boundSession: UserSession?
    private let target: UserAdministrationTarget?
    private let configurationUpdates: UserConfigurationUpdates?
    private let reads = LatestRequest<UserDto>()
    private let libraryReads = LatestRequest<[BaseItemDto]>()
    private let writes = LatestRequest<Void>()
    private let readGate = AsyncOperationGate()
    private let libraryGate = AsyncOperationGate()
    private let writeGate = AsyncOperationGate()
    private let configurationGate = AsyncOperationGate()

    init(user: UserDto) {
        self.user = user
        let session = Container.shared.currentUserSession()
        boundSession = session
        target = try? session?.userAdministration.target(userID: user.id ?? "")
        if let session, let id = user.id {
            configurationUpdates = id == session.user.id
                ? session.userConfigurationUpdates
                : session.userAdministration.configurationUpdates(userID: id)
        } else {
            configurationUpdates = nil
        }
        super.init()
        Notifications[.didChangeUserProfile].publisher
            .sink { [weak self] userID in
                guard let self, userID == target?.userID else { return }
                refresh()
            }
            .store(in: &cancellables)
    }

    private func checkBinding() throws {
        guard let target, let session = boundSession,
              Container.shared.userSessionManager().currentSession === session
        else { throw CancellationError() }
        try target.checkBinding()
    }

    private func checkpoint(_ gate: AsyncOperationGate) throws -> AsyncOperationGate.Checkpoint {
        try checkBinding()
        let generation = gate.begin()
        return { [weak self] in
            try generation()
            guard let self else { throw CancellationError() }
            try checkBinding()
            try generation()
        }
    }

    /// Current account settings are read from its live local snapshot at the press.
    var configuration: UserConfiguration? {
        do {
            try checkBinding()
            if let session = boundSession, target?.userID == session.user.id {
                return session.user.data.configuration
            }
            return user.configuration
        } catch { return nil }
    }

    func refresh() {
        guard let target, let check = try? checkpoint(readGate) else { return }
        let startingConfiguration = configuration
        let updates = configurationUpdates
        reads.replace(operation: {
            await updates?.waitUntilFinished()
            try check()
            return try await target.user()
        }, begin: { [weak self] in
            self?.background.states.insert(.refreshing)
        }, failure: { [weak self] failure in
            guard let self, (try? check()) != nil else { return }
            background.states.remove(.refreshing)
            guard (try? check()) != nil else { return }
            error = ErrorMessage(failure.localizedDescription)
            guard (try? check()) != nil else { return }
            state = .error
        }, receive: { [weak self] value in
            guard let self, (try? check()) != nil else { return }
            background.states.remove(.refreshing)
            guard (try? check()) != nil else { return }
            var refreshed = value
            if let session = boundSession, target.userID == session.user.id,
               session.user.data.configuration != startingConfiguration
            {
                refreshed.configuration = session.user.data.configuration
            }
            user = refreshed
            guard (try? check()) != nil else { return }
            if let session = boundSession, target.userID == session.user.id,
               session.user.data.configuration == startingConfiguration
            {
                session.user.data.configuration = refreshed.configuration
            }
            guard (try? check()) != nil else { return }
            state = .content
        })
    }

    func getLibraries(isHidden: Bool? = false) {
        guard let target, let check = try? checkpoint(libraryGate) else { return }
        libraryReads.replace(operation: {
            try check()
            return try await target.libraries(isHidden: isHidden)
        }, failure: { [weak self] failure in
            guard let self, (try? check()) != nil else { return }
            error = ErrorMessage(failure.localizedDescription)
        }, receive: { [weak self] value in
            guard let self, (try? check()) != nil else { return }
            libraries = value
        })
    }

    private func update(
        operation: @escaping @MainActor @Sendable () async throws -> Void,
        publish: @escaping @MainActor @Sendable (ServerUserAdminViewModel, AsyncOperationGate.Checkpoint) throws -> Void
    ) {
        guard let check = try? checkpoint(writeGate) else { return }
        reads.cancel()
        readGate.cancel()
        writes.replace(operation: {
            try check()
            try await operation()
            try check()
        }, begin: { [weak self] in
            guard let self, (try? check()) != nil else { return }
            background.states.remove(.refreshing)
            guard (try? check()) != nil else { return }
            background.states.insert(.updating)
        }, failure: { [weak self] failure in
            guard let self, (try? check()) != nil else { return }
            background.states.remove(.updating)
            guard (try? check()) != nil else { return }
            error = ErrorMessage(failure.localizedDescription)
        }, receive: { [weak self] in
            guard let self, (try? check()) != nil else { return }
            do {
                background.states.remove(.updating)
                try check()
                try publish(self, check)
                try check()
                events.send(.updated)
            } catch {}
        })
    }

    func updatePolicy(_ policy: UserPolicy) {
        guard let target else { return }
        update(operation: { try await target.updatePolicy(policy) }) { model, check in
            var user = model.user
            user.policy = policy
            model.user = user
            try check()
            if let session = model.boundSession, target.userID == session.user.id {
                session.user.data.policy = policy
            }
        }
    }

    func updateUsername(_ username: String) {
        guard let target else { return }
        update(operation: { try await target.updateUsername(username) }) { model, check in
            var user = model.user
            user.name = username
            model.user = user
            try check()
            if let session = model.boundSession, target.userID == session.user.id {
                session.user.data.name = username
            }
            try check()
            Notifications[.didChangeUserProfile].post(target.userID)
        }
    }

    func editConfiguration(_ modify: (inout UserConfiguration) -> Void) {
        guard let updates = configurationUpdates, var configuration,
              let check = try? checkpoint(configurationGate)
        else { return }
        modify(&configuration)
        do {
            try check()
            reads.cancel()
            readGate.cancel()
            background.states.remove(.refreshing)
            try check()
            try updates.submit(configuration, validate: check, willSubmit: { [weak self] value in
                guard let self, (try? check()) != nil else { return }
                configurationUpdating = true
                guard (try? check()) != nil else { return }
                var updated = user
                updated.configuration = value
                user = updated
                guard (try? check()) != nil else { return }
                if let session = boundSession, target?.userID == session.user.id {
                    session.user.data.configuration = value
                }
            }, failure: { [weak self] failure in
                guard let self, (try? check()) != nil else { return }
                configurationUpdating = false
                guard (try? check()) != nil else { return }
                error = ErrorMessage(failure.localizedDescription)
            }, completion: { [weak self] in
                guard let self, (try? check()) != nil else { return }
                configurationUpdating = false
                guard (try? check()) != nil else { return }
                events.send(.updated)
            })
            // A different control may supersede this shared writer's completion.
            // Clear this screen's activity after its own admitted tail drains.
            Task { [weak self] in
                await updates.waitUntilFinished()
                guard let self, (try? check()) != nil else { return }
                configurationUpdating = false
            }
        } catch {
            guard !(error is CancellationError), (try? check()) != nil else { return }
            self.error = ErrorMessage(error.localizedDescription)
        }
    }

    func cancel() {
        readGate.cancel()
        libraryGate.cancel()
        writeGate.cancel()
        configurationGate.cancel()
        reads.cancel()
        libraryReads.cancel()
        writes.cancel()
        configurationUpdating = false
        background = Activity()
        state = .initial
    }
}
