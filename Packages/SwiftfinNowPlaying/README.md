# SwiftfinNowPlaying

Owns system Now Playing metadata and remote media-command registration. The app passes immutable command events to its current playback owner; SDK callbacks and exact registration tokens stay internal.

Each configuration gets an owner/epoch lease. Reconfiguration rejects old callbacks even when the same controller remains alive. Authority is revoked before SDK cleanup; captured old and orphan registrations are removed without disabling newer commands through synchronous reentry. Dynamic publication checks the lease before reading shared metadata and between metadata/play-state writes. Already accepted SDK effects are not rolled back.

The optional handledByInterface command set acknowledges controls performed by native UI without forwarding playback twice. tvOS uses it for play/pause toggle; iOS forwards through its player owner. The app no longer removes all system toggle targets or installs an untracked global handler.

Controller, metadata and registry are main-actor owned. Command payloads are checked Sendable and reject non-finite or negative positions/intervals. Fifteen native tests use a synthetic output port, including nine stale/reentrant ownership regressions. The UIKit artwork fixture remains compile-only under the runtime hold. No actual Mac media-control state is touched by the native tests.
