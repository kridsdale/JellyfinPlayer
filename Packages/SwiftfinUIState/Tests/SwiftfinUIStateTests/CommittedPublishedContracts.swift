//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Combine
import SwiftfinUIState
import Testing

@MainActor
private final class CommittedModel {
    @CommittedPublished
    var value = 0
}

@Test @MainActor
func `committed publication observers read the emitted stored value`() {
    let model = CommittedModel()
    var reads: [Int] = []
    let subscription = model.$value.sink { value in
        MainActor.preconditionIsolated()
        #expect(model.value == value)
        reads.append(value)
    }
    model.value = 1
    model.value = 2
    #expect(reads == [0, 1, 2])
    withExtendedLifetime(subscription) {}
}

@Test @MainActor
func `reentrant terminal assignment supersedes remaining ready delivery`() {
    let model = CommittedModel()
    var values: [Int] = []
    let first = model.$value.sink {
        if $0 == 1 {
            model.value = 2
        }
    }
    let second = model.$value.sink { value in
        #expect(value == model.value)
        values.append(value)
    }
    model.value = 1
    // Combine does not promise subscriber order. A subscriber may see Ready
    // before the terminal subscriber runs, but never afterward as a stale value.
    #expect(model.value == 2 && values.last == 2)
    withExtendedLifetime((first, second)) {}
}

@Test @MainActor
func `publisher does not keep its value owner alive after release`() throws {
    var model: CommittedModel? = CommittedModel()
    weak let weakModel = model
    let publisher = try #require(model?.$value)
    var values: [Int] = []
    let subscription = publisher.sink { values.append($0) }
    model = nil
    #expect(weakModel == nil && values == [0])
    withExtendedLifetime((publisher, subscription)) {}
}
