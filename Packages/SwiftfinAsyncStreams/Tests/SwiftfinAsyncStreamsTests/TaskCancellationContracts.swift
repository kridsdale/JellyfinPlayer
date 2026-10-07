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
private final class Gate {
    var continuation: CheckedContinuation<Void, Never>?
    func wait() async {
        await withCheckedContinuation { continuation = $0 }
    }

    func release() {
        continuation?.resume()
        continuation = nil
    }
}

@MainActor
private func settle(_ condition: () -> Bool) async {
    for _ in 0 ..< 2000 {
        if condition() {
            return
        }
        await Task.yield()
    }
    #expect(condition())
}

@Suite("Task cancellation leases")
@MainActor
struct TaskCancellationContracts {
    @Test
    func `explicit repeated cancellation reaches the original suspended task`() async {
        let gate = Gate()
        let task = Task { await gate.wait()
            return Task.isCancelled
        }
        defer { task.cancel()
            gate.release()
        }
        await settle { gate.continuation != nil }
        let lease = task.asAnyCancellable()
        lease.cancel()
        lease.cancel()
        gate.release()
        #expect(await task.value)
    }

    @Test
    func `release and stored cancellation ownership cancel only their task`() async {
        for stored in [false, true] {
            let gate = Gate()
            let task = Task { await gate.wait()
                return Task.isCancelled
            }
            defer { task.cancel()
                gate.release()
            }
            await settle { gate.continuation != nil }
            if stored {
                var leases: Set<AnyCancellable> = []
                task.store(in: &leases)
                #expect(leases.count == 1)
                leases.removeAll()
            } else {
                var lease: AnyCancellable? = task.asAnyCancellable()
                #expect(lease != nil)
                lease = nil
            }
            gate.release()
            #expect(await task.value)
        }
    }
}
