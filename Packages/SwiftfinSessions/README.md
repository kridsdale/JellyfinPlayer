# SwiftfinSessions

Owns account resource lifecycle and latest-wins session replacement. Foundation only; no app globals, networking, persistence or UI.

`SessionResource` supplies prepare/start/stop. `SessionLifecycle` prepares and activates in order, stops in reverse order and rejects late preparation or reentrant activation after stop. `AccountSessionLifecycle` adds immutable identity; `ActiveSessionCoordinator` publishes only the latest prepared account before activation. All mutable ownership is on the main actor. The app supplies resource adapters and handles published identity effects.

Run `swift test --package-path Packages/SwiftfinSessions` for cancellation, ordering, replacement, idempotence, owner-release and reentrant-stop contracts.
