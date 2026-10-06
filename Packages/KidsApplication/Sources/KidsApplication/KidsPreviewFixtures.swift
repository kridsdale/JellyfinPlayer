//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import KidsCatalog
import KidsDomain
import KidsPlaybackSession

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
            let movie = scenario == "movie-paused"
            let title = model.catalog[movie ? .movies : .shows]![0]
            let episodes = movie ? [] : Self.episodes(showID: title.id)
            model.activePlayback = KidsPlaybackController.preview(
                item: movie ? title : episodes[0], title: title, mode: movie ? .movie : .ordered,
                episodes: episodes, delegate: model, scenario: scenario
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

#endif
