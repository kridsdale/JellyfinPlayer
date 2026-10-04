//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

// SPDX-License-Identifier: MPL-2.0
import AVFoundation
import Combine
import CoreData
import Defaults
import FactoryKit
import Foundation
import JellyfinAPI
import KidsCore
import KidsPersistence
import Security
import SwiftData
import UIKit

@MainActor
final class KidsAppModel: ObservableObject {
    @Published
    var category: KidsCategory = .shows
    @Published
    var catalog: [KidsCategory: [KidsItem]] = [:]
    @Published
    var loading = true
    @Published
    var problem: String?
    @Published
    var requiresParent = false
    @Published
    var needsLocalReset = false
    @Published
    var selectedShow: KidsItem?
    @Published
    var selectedMovie: KidsItem?
    @Published
    var starting = false
    var isPreview = false
    @Published
    var activePlayback: KidsPlaybackController?
    @Published
    var sessionFinished = false
    @Published
    var sessionEndItem: KidsItem?
    @Published
    var missingItemReplacement: KidsItem?
    @Published
    var parentPresented = false
    @Published
    var gate = KidsGate()
    @Published
    var state: KidsState?
    @Published
    var lastPlayback: Date?
    @Published
    var cloudSyncStatus = "Playback is saved on this Apple TV."
    private var persistence: KidsStateRepository?
    private var cloudActive = false
    private var syncBaseline: KidsSyncSnapshot?
    private var syncObservers = Set<AnyCancellable>()
    var lastFocus: [KidsCategory: String] = [:]
    var episodeCache: [String: [KidsItem]] = [:]
    var binding: KidsBinding? {
        state?.binding
    }

    var api: KidsAPI? {
        guard !isPreview, let session = Container.shared.currentUserSession() else { return nil }
        #if DEBUG
        // Opt-in integration faults use real HTTP errors without altering the saved account or server.
        if validationScenario == "unavailable" {
            return KidsAPI(serverURL: URL(string: "http://127.0.0.1:9")!, token: "invalid-validation-token")
        }
        if validationScenario == "invalid-token" {
            return KidsAPI(serverURL: session.server.effectiveServerURL, token: "invalid-validation-token")
        }
        #endif
        return KidsAPI(serverURL: session.server.effectiveServerURL, token: session.user.accessToken)
    }

    #if DEBUG
    private var validationStreamFailureUsed = false
    func consumeValidationStreamFailure() -> Bool {
        guard validationScenario == "stream-unavailable", !validationStreamFailureUsed else { return false }
        validationStreamFailureUsed = true
        return true
    }

    private var validationScenario: String? {
        ProcessInfo.processInfo.arguments.first(where: { $0.hasPrefix("--kids-validation=") })?
            .replacingOccurrences(of: "--kids-validation=", with: "")
    }
    #endif

    var serverName: String {
        Container.shared.currentUserSession()?.server.name ?? "Your Jellyfin server"
    }

    private var skipNextBrowseRefresh = true
    private var refreshGeneration = UUID()
    private var startTask: Task<Void, Never>?
    private var startGeneration = UUID()
    private var speechTask: Task<Void, Never>?
    private let speaker = AVSpeechSynthesizer()
    private var stateURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("KidsPlayer/state-v1.json")
    }

    private var cloudRequested: Bool {
        (Bundle.main.object(forInfoDictionaryKey: "KidsCloudSyncEnabled") as? String) == "YES"
    }

    private func repository() throws -> KidsStateRepository {
        if let persistence {
            return persistence
        }
        let defaults = UserDefaults.standard
        let writerKey = "kids.sync.installation.v1"
        let writerID = defaults.string(forKey: writerKey) ?? UUID().uuidString
        defaults.set(writerID, forKey: writerKey)
        let url = stateURL.deletingLastPathComponent().appendingPathComponent("progress.store")
        let container: ModelContainer
        do {
            container = try KidsStateRepository.makeContainer(url: url, cloud: cloudRequested)
            cloudActive = cloudRequested
            cloudSyncStatus = cloudRequested ? "iCloud sync configured. Updates sync when connected." :
                "Saved on this simulator. iCloud requires a signed iCloud-enabled build."
        } catch {
            guard cloudRequested else { throw error }
            // Opening the same SDK store locally retains durable progress if CloudKit
            // cannot initialize. No JSON fallback, store deletion or silent reset.
            container = try KidsStateRepository.makeContainer(url: url, cloud: false)
            cloudActive = false
            cloudSyncStatus = "Saved on this Apple TV. iCloud could not start; reopen the app to retry."
        }
        let store = KidsStateRepository(container: container, writerID: writerID)
        persistence = store
        return store
    }

    private func receiveStoredProgress() {
        guard !isPreview, !starting, activePlayback == nil, let binding, let persistence else { return }
        do {
            let restored = try persistence.load(binding: binding)
            syncBaseline = restored
            state = restored.state
        } catch { show(error) }
    }

    private func observeCloudChanges() {
        NotificationCenter.default.publisher(for: .NSPersistentStoreRemoteChange)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.receiveStoredProgress() }.store(in: &syncObservers)
        NotificationCenter.default.publisher(for: ModelContext.didSave)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.receiveStoredProgress() }.store(in: &syncObservers)
        NotificationCenter.default.publisher(for: NSPersistentCloudKitContainer.eventChangedNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] note in
                guard let self, self.cloudActive, let event = note.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey]
                    as? NSPersistentCloudKitContainer.Event, event.endDate != nil else { return }
                if event.succeeded {
                    if event.type == .export {
                        self.cloudSyncStatus = "Last iCloud save: " + event.endDate!.formatted(date: .abbreviated, time: .shortened)
                    }
                    if event.type == .import {
                        self.receiveStoredProgress()
                    }
                } else {
                    self.cloudSyncStatus = "Saved on this Apple TV. iCloud is waiting; it will retry automatically."
                }
            }.store(in: &syncObservers)
    }

    private let bindingKey = "kids.binding.v1"
    private let recoveryBindingKey = "kids.recoveryBinding.v1"
    private let gateKey = "kids.gate.v1"
    private let pinKey = "kids.parentPin.v1"
    var hasParentPIN: Bool {
        isPreview || Container.shared.keychainService().get(pinKey) != nil
    }

    var unlocked: Bool {
        gate.unlocked(at: .now)
    }

    init(preview: Bool = false) {
        if preview {
            isPreview = true
            return
        }
        observeCloudChanges()
        if let data = UserDefaults.standard.data(forKey: gateKey), let saved = try? JSONDecoder().decode(KidsGate.self, from: data) {
            gate = saved
            gate.lock()
        }
    }

    func enterBrowse() {
        guard !isPreview, !loading, !requiresParent, activePlayback == nil else { return }
        if skipNextBrowseRefresh {
            skipNextBrowseRefresh = false
            return
        }
        Task { await refresh() }
    }

    func refresh() async {
        guard !isPreview else { return }
        // Re-inserting the browse view after this refresh must not start another refresh loop.
        skipNextBrowseRefresh = true
        let generation = UUID()
        refreshGeneration = generation
        loading = true
        catalog = [:]
        episodeCache = [:]
        problem = nil
        needsLocalReset = false
        guard let api, let session = Container.shared.currentUserSession(),
              let data = UserDefaults.standard.data(forKey: bindingKey),
              let stored = try? JSONDecoder().decode(KidsBinding.self, from: data),
              stored.userID == session.user.id, stored.serverID == session.server.id
        else {
            state = nil
            selectedShow = nil
            selectedMovie = nil
            lastFocus = [:]
            await stopPlayback()
            loading = false
            requiresParent = true
            problem = "A grown-up needs to set up your shows."
            return
        }
        do {
            var expected = stored
            #if DEBUG
            if validationScenario == "changed-libraries" {
                expected = KidsBinding(
                    serverID: stored.serverID,
                    userID: stored.userID,
                    showsID: "invalid-validation-library",
                    moviesID: stored.moviesID
                )
            }
            #endif
            try await api.validate(expected)
            let restored = try repository().load(binding: stored, legacyURL: stateURL)
            async let shows = api.catalog(.shows, binding: stored)
            async let movies = api.catalog(.movies, binding: stored)
            let result = try await (shows, movies)
            guard generation == refreshGeneration, !Task.isCancelled else { return }
            syncBaseline = restored
            state = restored.state
            catalog = [.shows: result.0, .movies: result.1]
            requiresParent = !hasParentPIN
            loading = false
        } catch { guard generation == refreshGeneration else { return }
            show(error)
            loading = false
        }
    }

    func show(_ error: Error) {
        if error is CancellationError {
            return
        }
        catalog = [:]
        episodeCache = [:]
        if let error = error as? KidsAPIError {
            problem = error.localizedDescription
            requiresParent = error == .authentication || error == .policy || error == .libraryChanged
            if requiresParent {
                state = nil
                selectedShow = nil
                selectedMovie = nil
                sessionEndItem = nil
                lastFocus = [:]
                startTask?.cancel()
                Task { await stopPlayback() }
            }
        } else if (error as? KidsContractError) == .invalidStateVersion {
            requiresParent = true
            needsLocalReset = true
            state = nil
            problem = "A grown-up needs to restore playback settings."
        } else {
            problem = "Your shows are taking a break. Try again."
            requiresParent = false
        }
    }

    func episodes(for show: KidsItem) async throws -> [KidsItem] {
        #if DEBUG
        if isPreview {
            return KidsPreviewFixtures.episodes(showID: show.id)
        }
        #endif
        guard let api, let binding, KidsEligibility.permits(show, binding: binding),
              show.kind == .series else { throw KidsContractError.denied }
        let generation = refreshGeneration
        do {
            let items = try await api.episodes(showID: show.id, binding: binding)
            guard !Task.isCancelled, self.binding == binding, refreshGeneration == generation else {
                throw CancellationError()
            }
            episodeCache[show.id] = items
            return items
        } catch {
            guard !Task.isCancelled, self.binding == binding, refreshGeneration == generation else {
                throw CancellationError()
            }
            if let failure = error as? KidsAPIError, [.authentication, .policy, .libraryChanged].contains(failure) {
                self.show(failure)
            }
            throw error
        }
    }

    func persist(intent: KidsSyncWriteIntent = .edit) {
        guard !isPreview, let state else { return }
        do {
            let store = try repository()
            let baseline = try syncBaseline ?? store.load(binding: state.binding, legacyURL: stateURL)
            let activeKey = activePlayback.flatMap { controller -> String? in
                switch controller.mode {
                case .ordered: "ordered/" + controller.title.id
                case .movie: "movie/" + controller.item.id
                default: nil
                }
            }
            let saved = try store.commit(state, since: baseline, intent: intent, activeKey: activeKey)
            syncBaseline = saved
            self.state = saved.state
            if saved.invalidatesPlayback, let controller = activePlayback {
                controller.allowsCheckpoints = false
                cancelPendingStart()
                Task { await stopPlayback(endSession: false) }
            }
        } catch { problem = "Playback progress could not be saved. A grown-up can check storage." }
    }

    func savePreferences(limit: Int? = nil, spoken: Bool? = nil) {
        guard unlocked else { return }
        touchGate()
        if let limit, [0, 1, 2].contains(limit) {
            state?.preferences.episodeLimit = limit
        }
        if let spoken {
            state?.preferences.spokenNavigation = spoken
        }
        persist()
    }

    func chooseNext(_ item: KidsItem) {
        guard unlocked else { return }
        touchGate()
        do { try state?.setNext(item)
            persist()
        } catch { show(error) }
    }

    func resetProgress(showID: String) {
        guard unlocked else { return }
        touchGate()
        state?.ordered.removeValue(forKey: showID)
        state?.endSession()
        persist()
    }

    func resetMovie(_ item: KidsItem) {
        guard unlocked else { return }
        touchGate()
        state?.movies.removeValue(forKey: item.id)
        persist()
    }

    func resetLocalState() async throws {
        guard unlocked else { throw KidsContractError.denied }
        var confirmed = binding
        if confirmed == nil, let data = UserDefaults.standard.data(forKey: bindingKey) {
            confirmed = try? JSONDecoder().decode(KidsBinding.self, from: data)
        }
        guard let confirmed else { throw KidsContractError.denied }
        if !isPreview {
            guard let api, let session = Container.shared.currentUserSession(),
                  session.user.id == confirmed.userID, session.server.id == confirmed.serverID
            else { throw KidsAPIError.authentication }
            try await api.validate(confirmed)
        }
        await stopPlayback()
        if isPreview {
            state = KidsState(binding: confirmed)
        } else {
            let reset = try repository().reset(binding: confirmed)
            syncBaseline = reset
            state = reset.state
        }
        needsLocalReset = false
        touchGate()
        await refresh()
    }

    func narration(_ text: String, preview: Bool = false) {
        speechTask?.cancel()
        speaker.stopSpeaking(at: .immediate)
        guard preview || state?.preferences.spokenNavigation == true, !UIAccessibility.isVoiceOverRunning else { return }
        speechTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(650))
            guard !Task.isCancelled else { return }
            let utterance = AVSpeechUtterance(string: text)
            utterance.rate = 0.45
            self?.speaker.speak(utterance)
        }
    }

    func lockParents() {
        gate.lock()
        saveGate()
        speechTask?.cancel()
        speaker.stopSpeaking(at: .immediate)
    }

    func touchGate() {
        gate.touch(at: .now)
        saveGate()
    }

    func checkGate() {
        if !unlocked && parentPresented && hasParentPIN {
            gate.lock()
        }
    }

    private func saveGate() {
        guard !isPreview else { return }
        UserDefaults.standard.set(try? JSONEncoder().encode(gate), forKey: gateKey)
    }

    func setPIN(_ pin: String) throws {
        guard !isPreview else { throw KidsContractError.denied }
        guard !hasParentPIN || unlocked, (4 ... 8).contains(pin.count), pin.allSatisfy(\.isNumber) else { throw KidsContractError.denied }
        guard Container.shared.keychainService().set(pin, forKey: pinKey) else { throw KidsAPIError.invalidResponse }
        _ = gate.attempt(correct: true, now: .now)
        saveGate()
    }

    func unlock(_ pin: String) -> Bool {
        let correct = isPreview ? pin == "4242" : Container.shared.keychainService().get(pinKey) == pin
        let result = gate.attempt(correct: correct, now: .now)
        saveGate()
        return result
    }

    func signIn(urlText: String, username: String, password: String, parentPIN: String, recovering: Bool = false) async throws {
        guard !hasParentPIN || unlocked || recovering else { throw KidsContractError.denied }
        guard (4 ... 8).contains(parentPIN.count), parentPIN.allSatisfy(\.isNumber),
              parentPIN != password else { throw KidsContractError.denied }
        guard let url = URL(string: urlText.trimmingCharacters(in: .whitespacesAndNewlines)),
              ["http", "https"].contains(url.scheme?.lowercased()), url.host != nil, url.user == nil,
              url.password == nil else { throw KidsAPIError.connection }
        let info = try await KidsAPI(serverURL: url, token: "").serverInfo()
        let client = JellyfinClient(configuration: .swiftfinConfiguration(url: url))
        let result = try await client.signIn(username: username, password: password)
        guard let token = result.accessToken, let user = result.user, let userID = user.id else { throw KidsAPIError.authentication }
        let newAPI = KidsAPI(serverURL: url, token: token)
        let libraries = try await newAPI.libraries(userID: userID)
        guard let shows = libraries.first(where: { $0.name == "Kid TV" && $0.collectionType == "tvshows" }),
              let movies = libraries.first(where: { $0.name == "Kid Movies" && $0.collectionType == "movies" })
        else { throw KidsAPIError.libraryChanged }
        let binding = KidsBinding(serverID: info.id, userID: userID, showsID: shows.id, moviesID: movies.id)
        try await newAPI.validate(binding)
        let restored: KidsSyncSnapshot
        if recovering {
            guard let data = UserDefaults.standard.data(forKey: bindingKey) ?? UserDefaults.standard.data(forKey: recoveryBindingKey),
                  let previous = try? JSONDecoder().decode(KidsBinding.self, from: data), previous == binding
            else { throw KidsContractError.denied }
            // Verify the same restricted account and both library identities before resetting the gate.
            guard gate.attempt(correct: true, now: .now) else { throw KidsContractError.denied }
            restored = try repository().reset(binding: binding)
        } else {
            if hasParentPIN {
                guard Container.shared.keychainService().get(pinKey) == parentPIN else { throw KidsContractError.denied }
            }
            // Refreshing credentials for the same binding retains ordered progress, bags, and session budget.
            restored = try repository().load(binding: binding, legacyURL: stateURL)
        }
        try setPIN(parentPIN)
        await stopPlayback()
        let keychain = Container.shared.keychainService()
        guard keychain.set(token, forKey: "\(userID)-accessToken") else { throw KidsAPIError.invalidResponse }
        let server = ServerState(urls: [url], currentURL: url, name: info.name, id: info.id, userIDs: [userID])
        var servers = StoredValues[.Server.servers]
        servers.removeAll { $0.id == info.id }
        servers.append(server)
        StoredValues[.Server.servers] = servers
        let saved = UserState(id: userID, serverID: info.id, username: user.name ?? username)
        saved.data = user
        saved.accessPolicy = .none
        var users = StoredValues[.User.users]
        users.removeAll { $0.id == userID }
        users.append(saved)
        StoredValues[.User.users] = users
        let encodedBinding = try JSONEncoder().encode(binding)
        UserDefaults.standard.set(encodedBinding, forKey: bindingKey)
        UserDefaults.standard.set(encodedBinding, forKey: recoveryBindingKey)
        syncBaseline = restored
        state = restored.state
        // Use the existing session lifecycle for playback SDK integration, without exposing its library UI.
        try await Container.shared.userSessionManager().signIn(userID: userID)
        await refresh()
    }

    func signOut() async {
        guard unlocked else { return }
        await stopPlayback()
        catalog = [:]
        episodeCache = [:]
        lastFocus = [:]
        state = nil
        if let data = UserDefaults.standard.data(forKey: bindingKey) {
            UserDefaults.standard.set(data, forKey: recoveryBindingKey)
        }
        UserDefaults.standard.removeObject(forKey: bindingKey)
        await Container.shared.userSessionManager().signOut(reason: .explicit)
        lockParents()
        requiresParent = true
    }

    func play(
        _ title: KidsItem,
        mode: KidsPlaybackMode,
        explicitEpisode: KidsItem? = nil,
        retryItem: KidsItem? = nil,
        retryPosition: Double = 0,
        continuing: Bool = false
    ) {
        guard mode != .once || retryItem != nil || unlocked else { return }
        beginPlayback(
            title,
            mode: mode,
            explicitEpisode: explicitEpisode,
            retryItem: retryItem,
            retryPosition: retryPosition,
            continuing: continuing
        )
    }

    func playOnce(show: KidsItem, episode: KidsItem) {
        guard unlocked, let approvedBinding = binding, show.kind == .series,
              KidsEligibility.permits(show, binding: approvedBinding),
              KidsEligibility.permits(episode, binding: approvedBinding), episode.seriesID == show.id
        else { return }
        touchGate()
        Task {
            await stopPlayback()
            guard binding == approvedBinding else { return }
            // The protected action was authorized before the parent sheet dismissed and relocked.
            beginPlayback(show, mode: .once, explicitEpisode: episode)
        }
    }

    func startMovieOver(_ movie: KidsItem) {
        guard unlocked, let approvedBinding = binding, movie.kind == .movie,
              KidsEligibility.permits(movie, binding: approvedBinding) else { return }
        touchGate()
        Task {
            await stopPlayback()
            guard binding == approvedBinding else { return }
            // Stop checkpoints the old stream first; then discard that position for this explicit restart.
            state?.movies.removeValue(forKey: movie.id)
            persist()
            beginPlayback(movie, mode: .movie)
        }
    }

    private func beginPlayback(
        _ title: KidsItem,
        mode: KidsPlaybackMode,
        explicitEpisode: KidsItem? = nil,
        retryItem: KidsItem? = nil,
        retryPosition: Double = 0,
        continuing: Bool = false
    ) {
        guard startTask == nil, activePlayback == nil, let api, let binding else { return }
        starting = true
        sessionFinished = false
        missingItemReplacement = nil
        problem = nil
        let generation = UUID()
        startGeneration = generation
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(15))
            guard let self, self.startGeneration == generation, self.starting else { return }
            self.cancelPendingStart()
            self.problem = "This video is taking a break. Try again."
        }
        startTask = Task { [weak self] in
            guard let self else { return }
            defer {
                if self.startGeneration == generation {
                    self.startTask = nil
                    self.starting = false
                }
            }
            do {
                var item: KidsItem
                var position = 0.0
                var allEpisodes: [KidsItem] = []
                if title.kind == .series {
                    selectedShow = title
                    allEpisodes = try await episodes(for: title)
                    if let retryItem {
                        guard let current = allEpisodes.first(where: { $0.id == retryItem.id }) else { throw KidsContractError.unavailable }
                        item = current
                        position = retryPosition
                    } else if let explicitEpisode {
                        guard let current = allEpisodes.first(where: { $0.id == explicitEpisode.id })
                        else { throw KidsContractError.denied }
                        item = current
                    } else if mode == .shuffle, let retained = state?.session, retained.showID == title.id, retained.mode == .shuffle,
                              let id = retained.itemID
                    {
                        guard let current = allEpisodes.first(where: { $0.id == id }) else { throw KidsContractError.missingCursor }
                        item = current
                        position = retained.seconds
                    } else if mode == .shuffle {
                        guard let draw = try state?.nextShuffle(showID: title.id, episodes: allEpisodes)
                        else { throw KidsContractError.unavailable }
                        item = draw
                    } else {
                        guard let next = try state?.orderedNext(showID: title.id, episodes: allEpisodes)
                        else { throw KidsContractError.unavailable }
                        item = next.0
                        position = next.1
                    }
                } else {
                    item = title
                    if retryItem != nil {
                        position = retryPosition
                    } else if let progress = state?.movies[item.id], !progress.complete {
                        position = progress.seconds
                    }
                }
                let verified = try await api.authorize(itemID: item.id, expectedKind: item.kind, binding: binding)
                guard !Task.isCancelled, self.binding == binding else { return }
                if verified.kind == .episode {
                    guard verified.seriesID == title.id else { throw KidsContractError.denied }
                }
                let controller = try await KidsPlaybackController.prepare(
                    item: verified,
                    title: title,
                    mode: mode,
                    position: position,
                    episodes: allEpisodes,
                    model: self
                )
                guard !Task.isCancelled, self.binding == binding, startGeneration == generation else { await controller.stop()
                    return
                }
                activePlayback = controller
                controller.start()
            } catch {
                guard !Task.isCancelled, self.startGeneration == generation, self.binding == binding else { return }
                if (error as? KidsContractError) ==
                    .missingCursor
                {
                    missingItemReplacement = try? state?.missingSuccessor(showID: title.id, episodes: episodeCache[title.id] ?? [])
                    problem = missingItemReplacement == nil ? "This episode is missing. A grown-up can choose another." : "This episode is missing. You can choose the next picture."
                } else if (error as? KidsContractError) == .ambiguousEpisodes {
                    problem = "A grown-up needs to check episode numbering."
                } else {
                    show(error)
                }
            }
        }
    }

    func stopPlayback(endSession: Bool = true) async {
        startGeneration = UUID()
        startTask?.cancel()
        startTask = nil
        starting = false
        if let playback = activePlayback {
            await playback.stop()
        }
        activePlayback = nil
        if endSession {
            state?.endSession()
        }
        persist(intent: .playback)
    }

    func cancelPendingStart() {
        startGeneration = UUID()
        startTask?.cancel()
        startTask = nil
        starting = false
    }

    func background() {
        cancelPendingStart()
        lockParents()
        activePlayback?.pauseOnBackground()
    }

    func playbackBegan(_ controller: KidsPlaybackController) {
        guard activePlayback === controller else { return }
        do { try state?.began(item: controller.item, mode: controller.mode, showID: controller.title.id)
            lastPlayback = .now
            persist(intent: .playback)
        } catch { Task { await stopPlayback() }
            show(error)
        }
    }

    func playbackCheckpoint(_ controller: KidsPlaybackController, seconds: Double) {
        guard activePlayback === controller, controller.allowsCheckpoints else { return }
        state?.checkpoint(item: controller.item, mode: controller.mode, seconds: seconds)
        persist(intent: .playback)
    }

    func completed(_ controller: KidsPlaybackController) async {
        guard activePlayback === controller, controller.allowsCheckpoints else { return }
        do {
            let more = try state?.finished(item: controller.item, mode: controller.mode, episodes: controller.episodes) ?? false
            if !more {
                state?.endSession()
            }
            persist(intent: .playback)
            if more {
                controller.nextEpisode = controller.mode == .shuffle ? try state?.nextShuffle(
                    showID: controller.title.id,
                    episodes: controller.episodes
                ) : try state?.orderedNext(showID: controller.title.id, episodes: controller.episodes).0
                controller.countdown = 10
                controller.showCountdown = true
                persist(intent: .playback)
            }
            await controller.stop()
            if !more {
                activePlayback = nil
                sessionFinished = controller.mode == .ordered || controller.mode == .shuffle
                if sessionFinished {
                    sessionEndItem = controller.title
                }
            }
        } catch { await stopPlayback()
            show(error)
        }
    }

    func continuePlayback(_ controller: KidsPlaybackController) async {
        guard activePlayback === controller else { return }
        activePlayback = nil
        play(controller.title, mode: controller.mode, continuing: true)
    }
}
