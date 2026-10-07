# KidsPlayback

Owns small playback value policies: decoded-picture/advancing-clock readiness,
resume start normalization, native end tolerance and measured bitrate conversion.
The reporting compatibility alias delegates serialization to AsyncStreams.

`KidsPlaybackStartPosition` preserves ordinary finite seconds and converts them
to truncated Jellyfin ticks. Invalid, negative and overflowing positions restart
at zero. `PlaybackCompletionPolicy` preserves the installed one-second native
end tolerance; app composition handles missing runtime and selects Stop/Next.

Run `swift test --package-path Packages/KidsPlayback` for value contracts. Native
player handles, platform surfaces, session control and account admission remain
with their respective owners.
