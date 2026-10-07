//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation
@testable import SwiftfinImageProcessing
import Testing

@MainActor
private final class SyntheticSVGRender {
    let id: String
    init(_ id: String) {
        self.id = id
    }
}

@MainActor
private final class SyntheticSVGReference {
    weak var rendered: SyntheticSVGRender?
    init(_ rendered: SyntheticSVGRender?) {
        self.rendered = rendered
    }
}

@MainActor
struct SVGRenderStateContracts {
    @Test
    func `identical input reuses exactly one render`() {
        let state = SVGRenderState<SyntheticSVGRender>()
        var calls = 0
        let bytes = Data("synthetic-svg-a".utf8)
        #expect(state.update(bytes) { _ in calls += 1
            return SyntheticSVGRender("a")
        })
        let rendered = state.rendered
        #expect(!state.update(bytes) { _ in calls += 1
            return SyntheticSVGRender("duplicate")
        })
        #expect(calls == 1 && state.rendered === rendered)
    }

    @Test
    func `failed replacement retires previous render and memoizes failure`() {
        let state = SVGRenderState<SyntheticSVGRender>()
        state.update(Data([1])) { _ in SyntheticSVGRender("previous") }
        let previous = SyntheticSVGReference(state.rendered)
        var calls = 0
        #expect(state.update(Data([2])) { _ in calls += 1
            return nil
        })
        #expect(state.rendered == nil && previous.rendered == nil)
        #expect(!state.update(Data([2])) { _ in calls += 1
            return SyntheticSVGRender("wrong")
        })
        #expect(calls == 1 && state.rendered == nil)
    }

    @Test
    func `empty replacement never parses and clears old output`() {
        let state = SVGRenderState<SyntheticSVGRender>()
        state.update(Data([1])) { _ in SyntheticSVGRender("previous") }
        var calls = 0
        #expect(state.update(Data()) { _ in calls += 1
            return SyntheticSVGRender("wrong")
        })
        #expect(calls == 0 && state.rendered == nil)
    }

    @Test
    func `changed valid bytes replace output and reset allows retry`() {
        let state = SVGRenderState<SyntheticSVGRender>()
        state.update(Data([1])) { _ in SyntheticSVGRender("a") }
        let old = SyntheticSVGReference(state.rendered)
        state.update(Data([2])) { _ in SyntheticSVGRender("b") }
        #expect(old.rendered == nil && state.rendered?.id == "b")
        state.reset()
        #expect(state.rendered == nil)
        #expect(state.update(Data([2])) { _ in SyntheticSVGRender("retry") })
        #expect(state.rendered?.id == "retry")
    }

    @Test
    func `reentrant newer input cannot be overwritten by older parse output`() {
        let state = SVGRenderState<SyntheticSVGRender>()
        let changed = state.update(Data([1])) { _ in
            state.update(Data([2])) { _ in SyntheticSVGRender("newer") }
            return SyntheticSVGRender("obsolete")
        }
        #expect(!changed && state.rendered?.id == "newer")
        #expect(!state.update(Data([2])) { _ in SyntheticSVGRender("wrong") })
    }

    @Test
    func `reset during parse and owner release retire output`() {
        weak var output: SyntheticSVGRender?
        do {
            let state = SVGRenderState<SyntheticSVGRender>()
            #expect(!state.update(Data([1])) { _ in state.reset()
                return SyntheticSVGRender("obsolete")
            })
            #expect(state.rendered == nil)
            state.update(Data([2])) { _ in SyntheticSVGRender("current") }
            output = state.rendered
            #expect(output != nil)
        }
        #expect(output == nil)
    }
}
