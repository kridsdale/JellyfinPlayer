# SwiftfinVLC

Owns the pinned SwiftVLC 1.0.0 implementation: native media opening and transport, track selection, absolute resume seek, drawable rendering, bounded numeric startup observations and awaited output release. It imports no Jellyfin DTOs, account/session globals, Defaults or app view models.

The app supplies `VLCPlaybackRequest` only after its existing fresh authorization and item provider succeed. Stream and sidecar URLs are held in memory and request descriptions are redacted. `VLCPlaybackController` exposes a typed frame, numeric/typed events, a renderer, transport commands and an awaited shutdown. Raw player handles, SDK callbacks and track objects are internal.

The controller and native implementation are main-actor owners. Frames, requests, events and track IDs are checked Sendable values. Each rendered item has a UUID generation; callbacks from old surfaces and all callbacks after Stop are rejected. The host retains exact item/account checks, audio activation, parent authorization, progress reporting and queue policy.

Tests inject an internal native engine rather than opening files, network streams or system audio. The same adjacent test source is compiled in the tvOS validation host. Real approved-server playback separately validates actual decoding and rendering; fake-engine success does not establish those results.
