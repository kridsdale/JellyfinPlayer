//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Combine
import Foundation
import SwiftfinAsyncStreams
import Testing

@MainActor
private final class Source {
    var starts = 0
    var endings = 0
    var output: AsyncStream<Int>.Continuation?
    func stream() -> AsyncStream<Int> {
        starts += 1
        let (stream, continuation) = AsyncStream<Int>.makeStream()
        output = continuation
        continuation.onTermination = { [weak self] _ in
            Task { @MainActor [weak self] in self?.endings += 1 }
        }
        return stream
    }
}

@MainActor
private func until(_ predicate: () -> Bool) async {
    for _ in 0 ..< 300 where !predicate() {
        await Task.yield()
    }
}

@Suite(.serialized) @MainActor
struct PublisherContracts {
    @Test
    func `an unused publisher does not allocate a source`() async {
        let source = Source()
        let publisher = AsyncStreamPublishers.shared { source.stream() }
        await Task.yield()
        #expect(source.starts == 0)
        withExtendedLifetime(publisher) {}
    }

    @Test
    func `subscriptions share delivery and only the last cancellation releases the stream`() async {
        let source = Source()
        let publisher = AsyncStreamPublishers.shared { source.stream() }
        var first: [Int] = []
        var second: [Int] = []
        let a = publisher.sink { first.append($0) }
        let b = publisher.sink { second.append($0) }
        await until { source.starts == 1 }
        source.output?.yield(1)
        await until { first == [1] && second == [1] }
        a.cancel()
        await Task.yield()
        source.output?.yield(2)
        await until { second == [1, 2] }
        #expect(first == [1] && source.starts == 1 && source.endings == 0)
        b.cancel()
        await until { source.endings == 1 }
        #expect(source.endings == 1)
    }

    @Test
    func `background Combine subscription and cancellation enter the declared owner`() async {
        let source = Source()
        let publisher = AsyncStreamPublishers.shared { source.stream() }
        let subscription = publisher.subscribe(on: DispatchQueue.global()).sink { _ in }
        await until { source.starts == 1 }
        #expect(source.starts == 1)
        subscription.cancel()
        await until { source.endings == 1 }
        #expect(source.endings == 1)
    }

    @Test
    func `a later subscription starts a fresh source after full cancellation`() async {
        let source = Source()
        let publisher = AsyncStreamPublishers.shared { source.stream() }
        let first = publisher.sink { _ in }
        await until { source.starts == 1 }
        first.cancel()
        await until { source.endings == 1 }
        var values: [Int] = []
        let second = publisher.sink { values.append($0) }
        await until { source.starts == 2 }
        source.output?.yield(3)
        await until { values == [3] }
        #expect(source.starts == 2 && values == [3])
        second.cancel()
        await until { source.endings == 2 }
    }

    @Test
    func `natural completion remains terminal and cannot revive the old source`() async {
        let source = Source()
        let publisher = AsyncStreamPublishers.shared { source.stream() }
        var firstCompleted = false
        let first = publisher.sink(receiveCompletion: { _ in firstCompleted = true }, receiveValue: { _ in })
        await until { source.starts == 1 }
        source.output?.finish()
        await until { firstCompleted && source.endings == 1 }
        #expect(firstCompleted && source.endings == 1)
        var secondCompleted = false
        let second = publisher.sink(
            receiveCompletion: { _ in secondCompleted = true },
            receiveValue: { _ in Issue.record("Finished source emitted") }
        )
        await until { secondCompleted }
        #expect(secondCompleted && source.starts == 1)
        first.cancel()
        second.cancel()
    }

    @Test
    func `completion finishes subscribers and dropping the subscription releases its source`() async {
        let source = Source()
        let publisher = AsyncStreamPublishers.shared { source.stream() }
        var completed = false
        var subscription: AnyCancellable? = publisher.sink(receiveCompletion: { _ in completed = true }, receiveValue: { _ in })
        await until { source.starts == 1 }
        source.output?.finish()
        await until { completed }
        #expect(completed)
        subscription = nil
        #expect(subscription == nil)
    }
}
