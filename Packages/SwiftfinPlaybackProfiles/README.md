# SwiftfinPlaybackProfiles

Owns immutable codec/container/subtitle/player/resolution values, typed Jellyfin profile constructors and native/VLC compatibility profile assembly. SDK pin: Jellyfin 3.2.0. Direct local dependency: SwiftfinCollections.

Assembly consumes immutable PlaybackCapabilitySnapshot and PlaybackProfileSettings values. No hardware APIs, defaults, account/session globals, network requests or player objects enter this module. App composition captures live hardware and user settings; SwiftfinStoredValues owns installed defaults serialization, and presentation adapters own localized labels and UTType conversion. DTOs are an explicit SDK interoperability API.

The test fixture was captured from 26 original production files at commit 05bb0d31 before extraction. Only hardware/settings reads were replaced with deterministic inputs. It freezes 97 complete profiles covering player, compatibility, HDR, custom add/replace and transcode policies, resolution, bitrate and subtitle burn-in. Native Defaults representations were captured in an isolated random suite. Fixture generation never reads media or installed user preferences.

Run `swift test --package-path Packages/SwiftfinPlaybackProfiles`.
