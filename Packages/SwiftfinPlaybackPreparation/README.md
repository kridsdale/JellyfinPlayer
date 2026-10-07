# SwiftfinPlaybackPreparation

Owns fresh playback metadata/info, source/runtime/session normalization,
static/transcoded stream URL requests, bitrate bytes and preview tile requests.
One immutable scoped executor/URL port preserves account and timing-delegate
ownership; application settings/profile/native-item construction remain in the
composition layer. No automatic playback-info or video prefetch is implemented.
