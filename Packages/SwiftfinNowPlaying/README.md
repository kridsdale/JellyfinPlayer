# SwiftfinNowPlaying

Owns system Now Playing metadata and remote media-command registration. The app passes immutable command events to its current playback owner; SDK callbacks and exact registration tokens stay internal.

One process has one publication owner. A new owner revokes all old command tokens; old queued callbacks and late cleanup cannot change the new owner. Metadata publication also checks ownership. Paused seeks retain static metadata and publish fractional time with an explicit floating-point zero rate.

Controller, metadata and registry are main-actor owned. Command payloads are checked Sendable and reject non-finite or negative positions and intervals. Six native tests use a typed output port without changing the Mac's actual media controls.
