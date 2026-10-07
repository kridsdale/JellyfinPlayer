# Retained application responsibility review

The application is intended to retain composition and platform presentation. This is a source-reviewed ledger, not an automatic approval of files based on their folder, filename or import count. The full-client refactor remains active. Live simulator/server activity is held by the human.

## Reviewed boundaries at the date/program checkpoint

| Source or responsibility | Disposition | Source evidence and boundary |
| --- | --- | --- |
| Shared/Objects/CurrentDate.swift and ten iOS consumers | Moved to SwiftfinUIState; original file removed | The reusable observer and writable property wrapper belong to UI state. Main/common run-loop scheduling is preserved, native subscription cleanup stays on the main actor, and consumers import the owner explicitly. Tests inject a scheduler and wall clock. The old code ignored the supplied interval; the new scheduler receives valid fractional intervals and uses one second for invalid values. |
| Shared/Objects/EPG/Programming/ClampedProgram.swift and ProgramBlock.swift | Moved to SwiftfinMediaCatalog; original files removed | Clamping, short-program grouping, stable identity and explicit-time airing decisions operate only on immutable SDK values. They do not require UI, settings or application globals. Existing catalog ownership/dependencies suffice. Nine independently executed original scenarios preserve 14 blocks and 210 airing decisions. Invalid inverted windows now return an empty result rather than constructing an invalid ClosedRange. |
| Shared/Objects/EPG/EPGLayout.swift | Retained platform presentation | Device idiom and preferred UIKit font metrics choose UI column/row/ruler dimensions; width converts a time span to view coordinates. No server/catalog/settings mutation or resource lifecycle is implemented here. |
| Shared/Extensions/JellyfinAPI/UserDto.swift | Retained composition/display adapter | The profile wrapper builds an ImageSource from the AccountAccess owner; full-user lookup delegates to UserAdministration and supplies the existing localized missing-ID error. Native client/storage implementations do not live in this adapter. |
| Shared/Extensions/JellyfinAPI/DeviceProfile.swift | Retained application composition | Captures selected defaults/stored settings and native hardware capabilities, then delegates pure profile construction to SwiftfinPlaybackProfiles. The profile library does not resolve the current user or application Factory container. |
| Shared/Extensions/JellyfinAPI/SessionInfoDto.swift | Retained display/comparison adapter | Device/play-method display labels remain presentation. Comparable delegates ordering to ServerOperationsPolicy with an explicit captured time; ordering implementation is already owned by that library. |
| Shared/Extensions/JellyfinAPI/ChapterInfo.swift | Retained presentation plus a thin value conversion | FullInfo constructs poster labels, accessibility, image sources and SwiftUI overlays. Tick conversion delegates numeric duration representation to SwiftfinTime. This does not justify a package for the file itself. |
| Shared/Extensions/JellyfinAPI/PlayerStateInfo.swift | Thin SDK/value adapter; review deprecated consumer removal | Converts SDK ticks through SwiftfinTime for presentation. The deprecated integer-seconds projection needs whole-consumer review before removal; no storage/network/player implementation is present. |

## Mixed responsibilities still requiring work

`Shared/Extensions/JellyfinAPI/BaseItemDto/BaseItemDto.swift` is not approved as entirely presentation. Its now-playing/image-rendering/localized-label/selected-playback composition is interleaved with reusable metadata rules: person fields/crew merging, item availability, airing/progress calculations, stream classification, recording/missing state, component eligibility and parent identity. Source review must identify the correct existing metadata/catalog/media-state/track owner for each policy and preserve the original endpoint, optional-field and date semantics through independent fixtures. It also captures current account policy for play-button eligibility; only the account capture belongs at the composition boundary.

`BaseItemDto+Permissions.swift` likewise mixes current-session lookup with download/metadata/lyrics/subtitles permission decisions. Keep actor-isolated account capture in the app, move the pure decisions behind an explicit policy/value interface, and preserve the existing nil policy/flag behavior. These rules describe client presentation eligibility; the server remains authoritative for mutations.

`BaseItemPerson.swift` contains presentation conformances alongside crew classification and role-string parsing. Review those dependencies together with the item metadata rules. Its substring range handling needs malformed-input tests before declaring it robust; a clean compile cannot establish that.

The generic notification delivery/key implementation and the remaining library/view-model/content/queue adapters still need a body-level review. Direct request construction has already moved out, but that alone does not prove those sources retain only composition or UI state. Do not restore a catch-all facade or create a new package for every helper.

## Completion evidence still required

- Classify all retained sources, with actual body/consumer evidence for every retained or extracted responsibility.
- Review the complete public API/consumer graph and actor/resource lifetime contracts.
- Complete current whole-graph navigation, restricted-account playback/recovery and renderer/output cleanup after the human lifts the simulator hold.

Physical-device/live CloudKit/server boot/App Store release gates remain separate. Nothing in this review authorizes RAID access, household account/catalog changes, or resuming simulator testing.
