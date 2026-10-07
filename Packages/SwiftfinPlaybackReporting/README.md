# SwiftfinPlaybackReporting

Owns immutable playback report identity, SDK report payloads and paths, and the
shared finite serialized/coalescing queue via SwiftfinAsyncStreams. KidsPlayback
also uses the foundation-only queue without depending on Jellyfin networking.
Captured transport ownership intentionally survives UI account replacement so
old terminal cleanup cannot be redirected or lost. Start remains driven by the
player adapter (decoded-output proof for Kids). Timing delegates remain ports.
