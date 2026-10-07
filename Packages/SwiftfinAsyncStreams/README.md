# SwiftfinAsyncStreams

Owns the Combine/AsyncStream lifecycle bridge; no network SDK, account, storage or UI dependencies.

`AsyncStreamPublishers.shared` receives a main-actor source factory and returns a lazy Combine publisher. Concurrent subscribers share the source; final cancellation releases it, and resubscription after cancellation creates another source. Source creation and delivery use the main actor. Combine's subscription/completion/cancellation callbacks are defined outside actor isolation and can run on background queues. Immutable leases and a checked locked cancellation bit coordinate release without unsafe Sendable conformances.

Run `swift test --package-path Packages/SwiftfinAsyncStreams` for lazy allocation, broadcast/last-subscriber lifetime, background subscription/cancellation, restart and completion.

`LatestRequest<Value>` owns one replaceable UI-actor task. `begin` runs
synchronously before IO and is checked for cancellation/replacement reentry.
Only a current noncancelled request can deliver a value or the optional failure
callback. Cancellation and transport cancellation stay quiet.
`waitUntilFinished()` captures the task owned at entry. Callbacks should retain
presentation objects weakly. App composition uses `AsyncOperationGate` checkpoints
when one publication callback applies several synchronous effects.
