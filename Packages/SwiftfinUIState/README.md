# SwiftfinUIState

Owns UI value boxes, event/selection lifetime, timer-backed presentation and view
release callbacks. Platform view hierarchy and feature policies stay in the app.

`CommittedPublished<Value>` is an actor-qualified property wrapper for Equatable,
Sendable UI values. Storage changes before subscriber delivery; a weak current
value filter rejects an older emission after synchronous reentry. Its publisher
is for UI-actor consumers. Foreign SDK callbacks enter through the scoped stream
bridge rather than subscribing across executors directly. The player uses it for
phases and sends its existing ObservableObject invalidation after assignment.

Run `swift test --package-path Packages/SwiftfinUIState` for native value, timer,
selection, release and committed-publication contracts. These tests do not
execute a SwiftUI view or native media output.
