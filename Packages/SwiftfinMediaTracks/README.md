# SwiftfinMediaTracks

Owns immutable stream filtering/default selection, profile-driven track rebuild decisions, per-player index maps and pinned libVLC sidecar identity matching. Inputs are exact Jellyfin SDK 3.2.0 DTOs and SwiftfinPlaybackProfiles values. Foundation and CryptoKit only; no settings, account, network, UI or native player imports.

The app captures the compatibility mode that built the profile, then delegates policy. Native mpv track-object adaptation remains at its SDK composition boundary. Existing nil/-1 disable semantics, direct/transcode ordering and MD5(full authenticated URL)/spu matching remain unchanged. URLs are never logged or retained in the map.

MediaVideoQuality owns poster default-video selection across item/source streams, cropped-width-or-height resolution classification and Dolby Vision/HDR precedence. Immutable resolution/range values cross executors without UI, settings or playback handles. The app chooses localized labels; poster cutoffs deliberately remain distinct from inherited generic HD/4K flag thresholds.
