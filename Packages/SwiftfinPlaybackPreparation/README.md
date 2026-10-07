# SwiftfinPlaybackPreparation

Owns fresh playback metadata/info, source/runtime/session normalization,
static/transcoded stream URL requests, bitrate bytes and preview tile requests.
One immutable scoped executor/URL port preserves account and timing-delegate
ownership; application settings/profile/native-item construction remain in the
composition layer. No automatic playback-info or video prefetch is implemented.

`PlaybackConnection` captures one sender and URL port for an item. Its preparation
owner validates account/connection currentness; report clients retain the same
sender for terminal cleanup after replacement. The one-way dependency on
SwiftfinPlaybackReporting joins these two owners without exposing a mutable SDK
client. App composition supplies the same transport to both ports and carries
this connection through deferred starts and track rebuilds. The accountless
factory placeholder never prepares or reports media.
