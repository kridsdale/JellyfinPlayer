# SwiftfinMediaTracks

Owns immutable stream filtering/default selection, profile-driven track rebuild decisions, per-player index maps and pinned libVLC sidecar identity matching. Inputs are exact Jellyfin SDK 3.2.0 DTOs and SwiftfinPlaybackProfiles values. Foundation and CryptoKit only; no settings, account, network, UI or native player imports.

The app captures the compatibility mode that built the profile, then delegates policy. Native mpv track-object adaptation remains at its SDK composition boundary. Existing nil/-1 disable semantics, direct/transcode ordering and MD5(full authenticated URL)/spu matching remain unchanged. URLs are never logged or retained in the map.
