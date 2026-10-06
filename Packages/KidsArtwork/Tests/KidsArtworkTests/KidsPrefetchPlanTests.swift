//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

// SPDX-License-Identifier: MPL-2.0
@testable import KidsArtwork
import KidsCatalog
import KidsDiagnostics
import KidsDomain
import Testing

private let prefetchBinding = KidsBinding(serverID: "server", userID: "kid", showsID: "tv", moviesID: "movies")
private let prefetchShows = (0 ..< 8).map {
    KidsItem(id: "show-\($0)", name: "Fixture", kind: .series, libraryID: "tv", imageTag: "art", imageOwnerID: "show-\($0)")
}

@Test
func `prefetch selects only the focused show and at most three adjacent images`() {
    let plan = KidsPrefetchPlan.make(focusedID: "show-3", category: .shows, items: prefetchShows, binding: prefetchBinding)
    #expect(plan.show == prefetchShows[3])
    #expect(plan.artwork.map(\.id) == ["show-2", "show-3", "show-4"])
    for id in ["show-0", "show-7"] {
        #expect(KidsPrefetchPlan.make(focusedID: id, category: .shows, items: prefetchShows, binding: prefetchBinding).artwork.count == 2)
    }
}

@Test
func `prefetch ignores nonitem focus missing art and catalog objects with wrong libraries or owners`() {
    for id in [nil, "parents", "category-shows", "unlisted"] {
        let plan = KidsPrefetchPlan.make(focusedID: id, category: .shows, items: prefetchShows, binding: prefetchBinding)
        #expect(plan.artwork.isEmpty && plan.show == nil)
    }
    var items = prefetchShows
    items[2].libraryID = "adult"
    items[4].imageOwnerID = "elsewhere"
    items[3].imageTag = nil
    let plan = KidsPrefetchPlan.make(focusedID: "show-3", category: .shows, items: items, binding: prefetchBinding)
    #expect(plan.artwork.isEmpty)
    #expect(plan.show == items[3])
    items[3].libraryID = "adult"
    let denied = KidsPrefetchPlan.make(focusedID: "show-3", category: .shows, items: items, binding: prefetchBinding)
    #expect(denied.artwork.isEmpty && denied.show == nil)
}

@Test
func `movie prefetch contains artwork only and categories cannot be interchanged`() {
    let movie = KidsItem(id: "movie", name: "Fixture", kind: .movie, libraryID: "movies", imageTag: "art", imageOwnerID: "movie")
    let plan = KidsPrefetchPlan.make(focusedID: movie.id, category: .movies, items: [movie], binding: prefetchBinding)
    #expect(plan.artwork == [movie])
    #expect(plan.show == nil)
    let wrong = KidsPrefetchPlan.make(focusedID: "show-3", category: .movies, items: prefetchShows, binding: prefetchBinding)
    #expect(wrong.artwork.isEmpty && wrong.show == nil)
}
