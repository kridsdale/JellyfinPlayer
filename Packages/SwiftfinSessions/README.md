# SwiftfinSessions

Owns account resource lifecycle and latest-wins session replacement. Foundation only; no app globals, networking, persistence or UI.

`SessionResource` supplies prepare/start/stop. `SessionLifecycle` prepares and activates in order, stops in reverse order and rejects late preparation or reentrant activation after stop. `AccountSessionLifecycle` adds immutable identity; `ActiveSessionCoordinator` publishes only the latest prepared account before activation. All mutable ownership is on the main actor. The app supplies resource adapters and handles published identity effects.

Run `swift test --package-path Packages/SwiftfinSessions` for cancellation, ordering, replacement, idempotence, owner-release and reentrant-stop contracts.

`ActiveSessionCoordinator.replace(with:validate:)` borrows a main-actor Sendable checkpoint for the operation. Failed preflight leaves the active session untouched; checks after preparation and publication reject retired admission before resource start. `stop` clears owned fields before stop callbacks, protecting reentry. The nonthrowing overload retains quiet cancellation for existing callers. Publication that already passed a checkpoint is not undone. Four added admission/reentry contracts are part of the 29 native tests.
