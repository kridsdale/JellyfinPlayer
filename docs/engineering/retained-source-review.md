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

## Item projection and permission ownership (source reviewed)

The 34 reusable members formerly mixed into BaseItemDto/BaseItemPerson now delegate to four existing owners. No additional library was introduced. The original source bodies were independently executed with synthetic DTOs and a fixed clock before extraction, using the original pinned SDK and Algorithms revisions.

| Responsibility | Owner and retained composition |
| --- | --- |
| Person dates/location, component/rating/external-link facts | ItemMetadataFacts holds an immutable DTO and evaluates only the requested fact. App properties preserve their existing names and delegate. Whitespace-only production locations and zero ratings retain their original meaning. |
| Crew classification, stable credit merging and actor-role parsing | ItemMetadataPolicy preserves actor duplicates, nil IDs, first crew identity, stable distinct roles and space-only trimming. A malformed final suffix with reversed parentheses is omitted instead of constructing a trapping substring range. |
| Download, metadata, lyric and subtitle eligibility | ItemMetadataPolicy.permissions accepts an explicit optional policy and returns four immutable decisions. The app retains main-actor current-session capture; no current-user/global lookup enters the library. Playlist metadata still depends on canDelete, including for an administrator. These UI decisions do not replace server authorization. |
| Availability, signed tick conversion, program timing, parent identity and play-button type rules | CatalogItemState accepts a DTO and one explicit captured instant. Nested-program precedence and inclusive item end dates are retained; EPG block end dates remain half-open. Raw program progress retains the original nonfinite invalid-span behavior, while percentage requires a positive live span. Construction does not eagerly compute all projections. |
| Watched/favorite control type eligibility | UserMediaStatePolicy produces two immutable capabilities, distinct from directly playable content and account playback permission. |
| Raw item stream classification | MediaStreamKindPolicy filters by exact SDK kind and includes external/dropped/encoded streams. Playback selection/rebuild rules keep their separate exclusions. |

The seven original compatibility contracts compare 18,810 permission masks, 152 kind/missing/control masks, 270 role outputs, ten timing scenarios, eight credit scenarios, every kind's person/parent facts and every SDK stream kind. Fifteen adjacent regressions exercise malformed roles, nil/playlist/specific-policy grants, nested/inclusive/invalid dates, signed tick truncation, type capability differences and raw external-track behavior. The original compatibility fixture and neutral input builders live only in the development test harness. Its executable product still depends only on KidsDomain/KidsPersistence.

BaseItemDto's remaining bodies were reviewed in this extraction: localized titles/labels, UIKit now-playing image rendering, platform metadata assembly, ItemGenre display adapters, chapter-image presentation and selected playback-provider/current-account composition stay in the app. Request and image URL construction delegate to their existing owners. BaseItemPerson retains its Displayable/LibraryParent conformances and thin metadata adapters. This review does not approve unrelated files automatically.

## Content-provider and view-model bodies reviewed

`ViewModel.swift` retains main-actor Factory/logger/current-session composition. Its administration executor captures the exact session/client/manager and weakly checks that all three remain current before exposing the already-owned operation clients. `BaseFetchViewModel.swift` retains UI value/state publication and the asynchronous Stateful refresh adapter; its overridable getValue is an app feature hook, not a request implementation.

`ContentGroupViewModel.swift` delegates refresh coalescing, stale decisions and group resolution to SwiftfinPaging's ContentRefreshCoordinator. The app composes feature view-model operations and publishes the resulting UI groups after a cancellation check. Its notification subscription still depends on the unfinished delivery/actor review below.

`DefaultContentGroupProvider.swift` delegates bound home-view querying to MediaCatalog and retains settings-selected platform poster groups, display order and localized labels. `LiveTVGroupProvider.swift` assembles localized pills/router destinations and poster sections. `SearchContentGroupProvider.swift` composes the filter view model, type-specific groups and people group. These are inspected UI/composition bodies, not independent backend algorithms.

`ItemTypeContentGroupProvider.swift` combines presentation group construction with a pure box-set query workaround that adds userView to the item-type filter. That workaround belongs in query/catalog normalization; inspect existing normalization/endpoint consumers and capture its original behavior before extraction. Its full body remains unapproved until that rule and notification integration are resolved.

## Remaining mixed responsibilities

The generic notification delivery/key implementation still combines reusable payload encoding/decoding and Combine transport with Factory injection, application key definitions and UIKit/AVFoundation notifications. Separate the transport into the existing async-delivery owner while retaining platform key/account composition. Preserve Void notifications without userInfo, payload mismatch rejection, injected NotificationCenter selection, custom interruption decoding and main-actor accessibility reads. The five modifier/name-set consumers require an explicit generic/actor review.

EpisodeMediaPlayerQueue is an app-owned platform overlay and selected-playback-provider composer. Catalog adjacency already delegates to MediaCatalog with binding and generation checks; review cancellation/task ownership and notification delivery before classifying its entire body. The remaining library/view-model/content/queue adapters and full public API/consumer graph still need body-level review. Direct request construction/import counts alone do not prove they retain only composition or UI state.

## Completion evidence still required

- Classify all retained sources, with actual body/consumer evidence for every retained or extracted responsibility.
- Review the complete public API/consumer graph and actor/resource lifetime contracts.
- Complete current whole-graph navigation, restricted-account playback/recovery and renderer/output cleanup after the human lifts the simulator hold.

Physical-device/live CloudKit/server boot/App Store release gates remain separate. Nothing in this review authorizes RAID access, household account/catalog changes, or resuming simulator testing.
