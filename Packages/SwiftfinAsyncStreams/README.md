# SwiftfinAsyncStreams

Owns the Combine/AsyncStream lifecycle bridge; no network SDK, account, storage or UI dependencies.

`AsyncStreamPublishers.shared` receives a main-actor source factory and returns a lazy Combine publisher. Concurrent subscribers share the source; final cancellation releases it, and resubscription after cancellation creates another source. Source creation and delivery use the main actor. Combine's subscription/completion/cancellation callbacks are defined outside actor isolation and can run on background queues. Immutable leases and a checked locked cancellation bit coordinate release without unsafe Sendable conformances.

Run `swift test --package-path Packages/SwiftfinAsyncStreams` for lazy allocation, broadcast/last-subscriber lifetime, background subscription/cancellation, restart and completion.
