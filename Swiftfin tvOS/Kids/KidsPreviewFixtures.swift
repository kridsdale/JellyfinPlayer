//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import KidsCore
import SwiftUI

#if DEBUG
/// Synthetic catalog for SwiftUI Previews and simulator layout/remote tests.
/// It never reads server data, stores credentials, or writes playback state.
@MainActor
enum KidsPreviewFixtures {
    static let binding = KidsBinding(serverID: "preview-server", userID: "preview-kid", showsID: "preview-tv", moviesID: "preview-movies")
    static func episodes(showID: String) -> [KidsItem] {
        (1 ... (showID == "one-show" ? 1 : 4)).map { KidsItem(
            id: "\(showID)-episode-\($0)",
            name: "Episode \($0)",
            kind: .episode,
            libraryID: binding.showsID,
            seriesID: showID,
            season: $0 > 2 ? 2 : 1,
            episode: $0 > 2 ? $0 - 2 : $0,
            runtime: 600
        ) }
    }

    static func model(_ scenario: String) -> KidsAppModel {
        let model = KidsAppModel(preview: true)
        model.state = KidsState(binding: binding)
        model.loading = false
        model.catalogComplete = true
        model.catalog = [
            .shows: (1 ... 12).map { KidsItem(id: "show-\($0)", name: "Friendly Show \($0)", kind: .series, libraryID: binding.showsID) },
            .movies: (1 ... 8).map { KidsItem(
                id: "movie-\($0)",
                name: "Family Movie \($0)",
                kind: .movie,
                libraryID: binding.moviesID,
                runtime: 3600
            ) }
        ]
        if scenario == "movies" {
            model.category = .movies
        }
        if scenario == "movies-loading" {
            model.catalog.removeValue(forKey: .movies)
            model.category = .movies
        }
        if scenario == "empty" {
            model.catalog = [.shows: [], .movies: []]
        }
        if scenario == "again" {
            model.state?.ordered["show-1"] = KidsProgress(itemID: "show-1-episode-4", complete: true)
            model.state?.ordered["show-2"] = KidsProgress(itemID: "show-2-episode-4", complete: true)
        }
        if scenario == "resume" || scenario == "movie-paused" {
            model.state?.movies["movie-1"] = KidsProgress(itemID: "movie-1", seconds: 1200)
            model.category = .movies
        }
        if scenario == "one-episode" {
            model.catalog[.shows] = [KidsItem(
                id: "one-show",
                name: "One Episode Show",
                kind: .series,
                libraryID: binding.showsID
            )]
        }
        if scenario == "movie-complete" {
            model.state?.movies["movie-1"] = KidsProgress(itemID: "movie-1", complete: true)
            model.category = .movies
        }
        model.selectedShow = model.catalog[.shows]?.first
        if ["paused", "controls", "reconnecting", "countdown", "hidden-player", "movie-paused"]
            .contains(scenario)
        {
            model.activePlayback = KidsPlaybackController.preview(
                model: model,
                scenario: scenario
            )
        }
        if scenario == "denied" {
            // Seed a prior visible catalog, then use the production denial path to remove it.
            model.show(KidsAPIError.authentication)
        }
        if scenario == "offline" {
            model.catalog = [:]
            model.problem = KidsAPIError.connection.localizedDescription
        }
        if scenario == "loading" {
            model.loading = true
        }
        if scenario == "session-end" {
            model.sessionEndItem = model.selectedShow
            model.sessionFinished = true
        }
        return model
    }
}

#Preview("Shows - missing art and focus") { KidsRootView(model: KidsPreviewFixtures.model("shows")) }
#Preview("Movies - posters") { KidsRootView(model: KidsPreviewFixtures.model("movies")) }
#Preview("Authorization denied - prior catalog hidden") { KidsRootView(model: KidsPreviewFixtures.model("denied")) }
#Preview("Offline catalog - protected help") { KidsRootView(model: KidsPreviewFixtures.model("offline")) }
#Preview("Neutral loading") { KidsRootView(model: KidsPreviewFixtures.model("loading")) }
#Preview("Empty catalog") { KidsRootView(model: KidsPreviewFixtures.model("empty")) }
#Preview("Ordered series finished") { KidsTitleView(
    model: KidsPreviewFixtures.model("again"),
    item: KidsPreviewFixtures.model("again").catalog[.shows]![0]
) }
#Preview("Movie resume") { KidsTitleView(
    model: KidsPreviewFixtures.model("resume"),
    item: KidsPreviewFixtures.model("resume").catalog[.movies]![0]
) }
#Preview("One episode show") { KidsRootView(model: KidsPreviewFixtures.model("one-episode")) }
#Preview("Movie completed") { KidsRootView(model: KidsPreviewFixtures.model("movie-complete")) }
#Preview("Movie paused - parent restart") { KidsRootView(model: KidsPreviewFixtures.model("movie-paused")) }
#Preview("Player paused timeline") { KidsRootView(model: KidsPreviewFixtures.model("paused")) }
#Preview("Player hidden controls") { KidsRootView(model: KidsPreviewFixtures.model("hidden-player")) }
#Preview("Next episode countdown") { KidsRootView(model: KidsPreviewFixtures.model("countdown")) }
#Preview("Player reconnecting") { KidsRootView(model: KidsPreviewFixtures.model("reconnecting")) }
#Preview("Session end with artwork") { KidsRootView(model: KidsPreviewFixtures.model("session-end")) }
#Preview("Parent gate") { KidsParentView(model: KidsPreviewFixtures.model("shows")) }
#endif
