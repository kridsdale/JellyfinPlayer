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
import FactoryKit
import KidsCore
import SwiftUI

private let kidsTeal = Color(red: 0.04, green: 0.47, blue: 0.49)
private let kidsBackground = Color(red: 0.055, green: 0.10, blue: 0.14)

struct KidsRootView: View {
    @StateObject
    private var model: KidsAppModel
    init(model: KidsAppModel? = nil) {
        _model = StateObject(wrappedValue: model ?? KidsAppModel())
    }

    @Environment(\.scenePhase)
    private var scenePhase
    @InjectedObject(\.userSessionManager)
    private var sessions
    @State
    private var path: [KidsItem] = []
    private let gateTimer = Timer.publish(every: 5, on: .main, in: .common).autoconnect()
    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if model.loading {
                    KidsStatusView(symbol: "tv", title: "Finding your shows…")
                } else if model.requiresParent || !model.hasParentPIN {
                    KidsStatusView(
                        symbol: "person.crop.circle.badge.checkmark",
                        title: "A grown-up can help.",
                        detail: model.problem,
                        actionTitle: "Parents",
                        actionSymbol: "lock.fill"
                    ) {
                        model.parentPresented = true
                    }
                } else if model.problem != nil && model.catalog.isEmpty {
                    KidsStatusView(symbol: "wifi.slash", title: "Your shows are taking a break.") { Task { await model.refresh() } }
                } else {
                    KidsBrowseView(model: model, path: $path)
                }
            }
            .navigationDestination(for: KidsItem.self) { item in
                if !model.requiresParent, model.catalog.values.contains(where: { $0.contains(item) }) {
                    KidsTitleView(
                        model: model,
                        item: item
                    )
                } else {
                    KidsStatusView(
                        symbol: "lock.fill",
                        title: "A grown-up can help.",
                        actionTitle: "Parents",
                        actionSymbol: "lock.fill"
                    ) { model.parentPresented = true }
                }
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        .tint(kidsTeal).preferredColorScheme(.dark).background(kidsBackground)
        .sheet(
            isPresented: Binding(get: { model.parentPresented && model.activePlayback == nil }, set: { model.parentPresented = $0 }),
            onDismiss: { model.lockParents() }
        ) { KidsParentView(model: model) }
        .fullScreenCover(item: $model.activePlayback) { playback in KidsPlayerView(model: model, playback: playback) }
        .sheet(isPresented: $model.sessionFinished) {
            VStack(spacing: 35) {
                if let title = model.sessionEndItem {
                    KidsArtwork(model: model, item: title, wide: true).frame(width: 550)
                }
                Text("All done for now!").font(.largeTitle.bold())
                Button("Back to shows", systemImage: "tv") {
                    model.sessionFinished = false
                    path = []
                    model.category = .shows
                }.buttonStyle(.borderedProminent)
            }.frame(maxWidth: .infinity, maxHeight: .infinity).background(kidsBackground)
                .onExitCommand { model.sessionFinished = false
                    path = []
                    model.category = .shows
                }
        }
        .task { await model.refresh() }
        .onChange(of: sessions.currentSession?.user.id) { path = []
            Task { await model.stopPlayback(endSession: false)
                await model.refresh()
            }
        }
        .onChange(of: sessions.currentSession?.server.id) { path = []
            Task { await model.stopPlayback(endSession: false)
                await model.refresh()
            }
        }
        .onChange(of: scenePhase) {
            if scenePhase != .active {
                model.background()
            } else if model.activePlayback == nil {
                Task { await model.refresh() }
            }
        }
        .onChange(of: model.requiresParent) {
            if model.requiresParent {
                path = []
            }
        }
        .onReceive(gateTimer) { _ in model.checkGate() }
        // v1 intentionally has no item/account deep-link route. Incoming URLs cannot switch identity or escape the approved catalog.
    }
}

struct KidsStatusView: View {
    let symbol: String
    let title: String
    var detail: String?
    var actionTitle = "Try again"
    var actionSymbol = "arrow.clockwise"
    var action: (() -> Void)?
    var body: some View {
        VStack(spacing: 35) {
            Image(systemName: symbol).font(.system(size: 100)).foregroundStyle(.mint)
            Text(title).font(.largeTitle.bold())
            if let detail {
                Text(detail).font(.title3).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 850)
            }
            if let action {
                Button(actionTitle, systemImage: actionSymbol, action: action).buttonStyle(.borderedProminent)
            } else {
                ProgressView().scaleEffect(1.5)
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity).background(kidsBackground)
    }
}

struct KidsArtwork: View {
    @ObservedObject
    var model: KidsAppModel
    let item: KidsItem
    var wide = false
    @State
    private var image: UIImage?
    private var scope: String {
        "\(model.binding?.serverID ?? ""):\(model.binding?.userID ?? ""):\(model.binding?.showsID ?? ""):\(model.binding?.moviesID ?? ""):\(item.id):\(item.imageTag ?? "")"
    }

    private var placeholderColor: Color {
        let colors: [Color] = [kidsTeal, .indigo, .brown, .purple, .blue, .orange]
        return colors[item.id.utf8.reduce(0) { ($0 + Int($1)) % colors.count }]
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 24).fill(placeholderColor.gradient)
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Image(systemName: item.kind == .movie ? "film.fill" : "tv.fill").resizable().scaledToFit().padding(55)
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
        .aspectRatio(wide ? 1.65 : (item.kind == .movie ? 0.68 : 1.3), contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .accessibilityHidden(true)
        .task(id: scope) {
            image = nil
            guard let api = model.api, let binding = model.binding,
                  let request = try? api.imageRequest(for: item, binding: binding) else { return }
            let config = URLSessionConfiguration.ephemeral
            config.urlCache = nil
            do {
                let (data, response) = try await URLSession(configuration: config).data(for: request)
                guard !Task.isCancelled, model.binding == binding else { return }
                if let status = (response as? HTTPURLResponse)?.statusCode,
                   status == 401 || status == 403
                {
                    model.show(KidsAPIError.authentication)
                    return
                }
                guard (response as? HTTPURLResponse)?.statusCode == 200 else { return }
                image = UIImage(data: data)
            } catch { /* Missing artwork has an explicit, accessible placeholder. */ }
        }
    }
}

struct KidsBrowseView: View {
    @ObservedObject
    var model: KidsAppModel
    @Binding
    var path: [KidsItem]
    @FocusState
    private var focused: String?
    var body: some View {
        VStack(spacing: 36) {
            HStack(spacing: 30) {
                ForEach(KidsCategory.allCases, id: \.self) { category in
                    Button { model.category = category } label: {
                        Label(category.title, systemImage: category.symbol).font(.title2.bold()).padding(.horizontal, 20)
                    }
                    .buttonStyle(.bordered).tint(model.category == category ? kidsTeal : .gray)
                    .accessibilityIdentifier("kids.category.\(category.rawValue)")
                    .focused($focused, equals: "category-\(category.rawValue)")
                }
                Spacer()
                Button { model.parentPresented = true } label: { Label("Parents", systemImage: "lock.fill").font(.headline) }
                    .accessibilityIdentifier("kids.parents")
                    .focused($focused, equals: "parents")
            }
            if let items = model.catalog[model.category], !items.isEmpty {
                ScrollView {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 32), count: 4), spacing: 40) {
                        ForEach(items) { item in
                            Button {
                                model.lastFocus[model.category] = item.id
                                if item.kind == .series {
                                    model.selectedShow = item
                                }
                                path.append(item)
                            } label: {
                                VStack(spacing: 14) {
                                    KidsArtwork(model: model, item: item).frame(height: 310)
                                    Text(item.name).font(.headline).lineLimit(1)
                                }.padding(8)
                            }
                            .buttonStyle(.card).focused($focused, equals: item.id)
                            .accessibilityLabel(item.name).accessibilityIdentifier("kids.card.\(item.id)")
                        }
                    }.padding(.vertical, 24)
                }
                .scrollClipDisabled()
            } else {
                KidsStatusView(
                    symbol: model.category.symbol,
                    title: "More pictures are coming!",
                    actionTitle: "\(model.category == .shows ? "Movies" : "Shows")"
                ) {
                    model.category = model.category == .shows ? .movies : .shows
                }
            }
        }
        .padding(.horizontal, 70).padding(.top, 45).background(kidsBackground)
        .onAppear { focused = model.lastFocus[model.category] ?? model.catalog[model.category]?.first?.id }
        .onChange(of: focused) {
            if focused == "parents" {
                model.narration("Parents")
            } else if let category = KidsCategory.allCases.first(where: { "category-\($0.rawValue)" == focused }) {
                model.narration(category.title)
            } else if let item = model.catalog[model.category]?.first(where: { $0.id == focused }) {
                model.lastFocus[model.category] = item.id
                model.narration(item.name)
            }
        }
        .onExitCommand(perform: model.category == .movies ? { model.category = .shows } : nil)
    }
}

struct KidsTitleView: View {
    @ObservedObject
    var model: KidsAppModel
    let item: KidsItem
    @State
    private var episodes: [KidsItem] = []
    @State
    private var loading = true
    @State
    private var error: String?
    @FocusState
    private var focused: String?
    private var again: Bool {
        model.state?.ordered[item.id]?.complete == true
    }

    var body: some View {
        VStack(spacing: 30) {
            HStack(alignment: .center, spacing: 75) {
                KidsArtwork(model: model, item: item, wide: item.kind != .movie).frame(width: item.kind == .movie ? 400 : 680)
                VStack(alignment: .leading, spacing: 40) {
                    Text(item.name).font(.system(size: 54, weight: .bold)).lineLimit(3)
                    if loading {
                        ProgressView()
                    } else if let error {
                        Text(error).font(.title3)
                        Button("Try again") { Task { await load() } }
                    } else if item.kind == .series {
                        HStack(spacing: 32) {
                            bigAction(again ? "Again" : "Next", symbol: again ? "arrow.counterclockwise" : "play.fill", id: "next") {
                                model.play(
                                    item,
                                    mode: .ordered
                                )
                            }
                            bigAction("Shuffle", symbol: "dice.fill", id: "shuffle") { model.play(item, mode: .shuffle) }
                        }
                    } else {
                        let progress = model.state?.movies[item.id]
                        let resume = progress != nil && progress?.complete != true && (progress?.seconds ?? 0) > 0
                        if resume, let runtime = item.runtime, runtime > 0 {
                            ProgressView(
                                value: min(progress?.seconds ?? 0, runtime),
                                total: runtime
                            ).frame(width: 360).accessibilityLabel("Movie progress")
                        }
                        bigAction(
                            resume ? "Resume" : (progress?.complete == true ? "Play again" : "Play"),
                            symbol: "play.fill",
                            id: "play"
                        ) { model.play(item, mode: .movie) }
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            if let replacement = model.missingItemReplacement, replacement.seriesID == item.id {
                HStack(spacing: 30) {
                    KidsArtwork(model: model, item: replacement, wide: true).frame(width: 240)
                    Button("Next available", systemImage: "play.fill") { model.play(item, mode: .ordered, explicitEpisode: replacement) }
                        .buttonStyle(.borderedProminent)
                }
            }
            if let problem = model.problem {
                Text(problem).font(.title3).foregroundStyle(.orange)
            }
            HStack { Spacer()
                Button("Parents", systemImage: "lock.fill") { model.selectedShow = item.kind == .series ? item : model.selectedShow
                    model.parentPresented = true
                }
            }
        }
        .padding(80).frame(maxWidth: .infinity, maxHeight: .infinity).background(kidsBackground)
        .task {
            if item.kind == .movie {
                model.selectedMovie = item
            }
            await load()
        }
        .onDisappear {
            if model.activePlayback == nil {
                model.cancelPendingStart()
            }
        }
        .onChange(of: model.activePlayback == nil) {
            if model.activePlayback == nil {
                focused = item.kind == .series ? "next" : "play"
            }
        }
        .onChange(of: focused) {
            if let focused {
                let label = focused == "shuffle" ? (episodes.count == 1 ? "Shuffle. This show has one episode." : "Shuffle") :
                    (item
                        .kind == .movie ?
                        (model.state?.movies[item.id]?
                            .complete == true ? "Play again" : ((model.state?.movies[item.id]?.seconds ?? 0) > 0 ? "Resume" : "Play")) :
                        (again ? "Again" : "Next"))
                model.narration(label)
            }
        }
    }

    private func bigAction(_ title: String, symbol: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 18) { Image(systemName: symbol).font(.system(size: 58))
                Text(title).font(.title2.bold()).lineLimit(1).minimumScaleFactor(0.8)
            }.frame(width: item.kind == .movie ? 300 : 205, height: 165)
        }.buttonStyle(.borderedProminent).focused($focused, equals: id).accessibilityIdentifier("kids.action.\(id)")
            .disabled(model.starting)
    }

    private func load() async {
        loading = true
        error = nil
        do {
            if item.kind == .series {
                episodes = try await model.episodes(for: item)
            }
            loading = false
            focused = item.kind == .series ? "next" : "play"
        } catch { loading = false
            self.error = "A grown-up can check this show."
        }
    }
}

struct KidsPlayerView: View {
    @ObservedObject
    var model: KidsAppModel
    @ObservedObject
    var playback: KidsPlaybackController
    @FocusState
    private var control: String?
    @Environment(\.scenePhase)
    private var phase
    @StateObject
    private var containerState = VideoPlayerContainerState()
    var body: some View {
        ZStack {
            Color.black
            if !model.isPreview {
                playback.proxy.videoPlayerBody
                    .environmentObject(playback.manager).environmentObject(containerState)
                    .ignoresSafeArea()
            }
            if !playback.controlsVisible && !playback.recovery && !playback.showCountdown && !playback.buffering {
                Button { playback.reveal() } label: { Color.clear.contentShape(Rectangle()) }
                    .buttonStyle(.plain).focusEffectDisabled()
                    .accessibilityLabel("Playback controls").accessibilityIdentifier("kids.player.surface")
            }
            if playback.showCountdown {
                VStack(spacing: 35) {
                    if let next = playback.nextEpisode {
                        KidsArtwork(model: model, item: next, wide: true).frame(width: 500)
                    }
                    Text("Next episode in \(playback.countdown)").font(.largeTitle.bold())
                    Button("Stop", systemImage: "stop.fill") { Task { await model.stopPlayback() } }
                        .buttonStyle(.borderedProminent).focused($control, equals: "stop")
                }.frame(maxWidth: .infinity, maxHeight: .infinity).background(.black.opacity(0.9))
                    .defaultFocus($control, "stop")
                    .onAppear { control = "stop" }
            } else if playback.recovery {
                VStack {
                    KidsStatusView(symbol: "wifi.slash", title: "Let's try that again.") { Task { await playback.retry() } }
                    Button("Back", systemImage: "arrow.backward") { Task { await model.stopPlayback() } }.padding(.bottom, 70)
                }
            } else if playback.buffering {
                ProgressView().scaleEffect(2)
            } else if playback.controlsVisible {
                VStack {
                    Spacer()
                    Text(playback.item.name).font(.title2.bold()).lineLimit(2)
                    if playback.paused {
                        VStack {
                            ProgressView(
                                value: min(playback.seconds, playback.item.runtime ?? playback.seconds),
                                total: max(1, playback.item.runtime ?? playback.seconds)
                            )
                            Text(time(playback.seconds) + " / " + time(playback.item.runtime ?? 0)).font(.headline.monospacedDigit())
                        }.padding(22).background(control == "timeline" ? kidsTeal : .clear, in: RoundedRectangle(cornerRadius: 16))
                            .frame(maxWidth: 1000).focusable().focused($control, equals: "timeline")
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel("Playback position").accessibilityIdentifier("kids.player.timeline")
                            .accessibilityValue(time(playback.seconds))
                            .accessibilityAdjustableAction { playback.seek($0 == .increment ? 15 : -15) }
                            .onMoveCommand { direction in
                                if control ==
                                    "timeline"
                                {
                                    if direction == .left {
                                        playback.seek(-15)
                                    } else if direction == .right {
                                        playback.seek(15)
                                    }
                                }
                            }
                    }
                    HStack(spacing: 40) {
                        Button(playback.paused ? "Play" : "Pause", systemImage: playback.paused ? "play.fill" : "pause.fill") {
                            playback.toggle()
                        }
                        .focused($control, equals: "playpause").accessibilityIdentifier("kids.player.playpause")
                        Button("Parents", systemImage: "lock.fill") { playback.pauseOnBackground()
                            model.parentPresented = true
                        }.accessibilityIdentifier("kids.player.parents")
                    }.buttonStyle(.borderedProminent)
                }.padding(65).background(LinearGradient(colors: [.clear, .black.opacity(0.9)], startPoint: .top, endPoint: .bottom))
                    .defaultFocus($control, "playpause")
                    .onAppear { control = "playpause" }
            }
        }
        .ignoresSafeArea()
        .onPlayPauseCommand { playback.toggle() }
        .onExitCommand { Task { await playback.handleBack() } }
        .onMoveCommand { _ in playback.reveal() }
        .onTapGesture { playback.reveal() }
        .onChange(of: phase) {
            if phase != .active {
                playback.pauseOnBackground()
            }
        }
        .sheet(isPresented: $model.parentPresented, onDismiss: { model.lockParents() }) { KidsParentView(model: model) }
    }

    private func time(_ value: Double) -> String {
        let v = max(0, Int(value.isFinite ? value : 0))
        return "\(v / 60):\(String(format: "%02d", v % 60))"
    }
}

#Preview("Loading") { KidsStatusView(symbol: "tv", title: "Finding your shows…") }
#Preview("Network unavailable") { KidsStatusView(symbol: "wifi.slash", title: "Your shows are taking a break.", action: {}) }
#Preview("Session finished") { KidsStatusView(
    symbol: "moon.stars.fill",
    title: "All done for now!",
    actionTitle: "Back to shows",
    action: {}
) }
