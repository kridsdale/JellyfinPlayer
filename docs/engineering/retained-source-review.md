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

`ContentGroupViewModel.swift` delegates refresh coalescing, stale decisions and group resolution to SwiftfinPaging's ContentRefreshCoordinator. The app composes feature view-model operations and publishes the resulting UI groups after a cancellation check. Its custom metadata notifications now use actor-bound app keys and retain synchronous posting delivery; the source-reviewed boundary is described below.

`DefaultContentGroupProvider.swift` delegates bound home-view querying to MediaCatalog and retains settings-selected platform poster groups, display order and localized labels. `LiveTVGroupProvider.swift` assembles localized pills/router destinations and poster sections. `SearchContentGroupProvider.swift` composes the filter view model, type-specific groups and people group. These are inspected UI/composition bodies, not independent backend algorithms.

`ItemTypeContentGroupProvider.swift` combines presentation group construction with a pure box-set query workaround that adds userView to the item-type filter. That workaround now delegates to MediaCatalogPolicy.groupedItemTypes, with all original kind outputs and query scope verified. The remaining group/label/filter composition is retained.

## Notification and query boundaries (source reviewed)

Generic notification transport now belongs to SwiftfinAsyncStreams. NotificationEvent is immutable and checked Sendable, with a Sendable payload and decoder, explicit center inputs and the original synchronous raw delivery/typed/Void semantics. Its main-actor status reader forwards only a Void signal before main-queue scheduling. The signal projection is constructed in a nonisolated helper so foreign native callbacks do not inherit an actor assertion. The original raw trace is independently captured and compared, including wrong/missing payloads, foreign names/centers, custom decoding, cancellation and Void decoder bypass.

The app's Notifications.Key retains Factory center selection and application/platform key names, and binds constructor/post/publisher access to the main actor. MainActorKey delegates platform status reading to the library bridge. All static key definitions and platform decode bodies are preserved. The three SwiftUI generic adapters and View.onNotification now require Sendable payloads; NotificationSet retains only UI name-set membership using immutable nonisolated key names. The audio-interruption consumer already receives on the main queue. The raw transport does not promise main-actor delivery to arbitrary library subscribers; that scheduling remains explicit.

The item-type provider's single box-set rule now delegates to MediaCatalogPolicy.groupedItemTypes. All 37 independently captured kind outputs match. The workaround applies only when that explicit group helper is used; other/mixed filters are unchanged. Adjacent parameter contracts preserve exact parent/user IDs, tags, page bounds and folder recursion. ItemTypeContentGroupProvider retains only platform group/label/selected-filter composition.

## Remaining mixed responsibilities

EpisodeMediaPlayerQueue is an app-owned platform overlay and selected-playback-provider composer. Catalog adjacency delegates to MediaCatalog with exact binding checks; LatestRequest now owns request generation/cancellation/release. Its manager subscription is independent of base session subscriptions, and its weak publication requires a live manager. Provider/resume/bitrate and overlay bodies are unchanged. The remaining library/view-model/content/queue adapters and full public API/consumer graph still need body-level review. Direct request construction/import counts alone do not prove they retain only composition or UI state.

## Additional service and supplement bodies reviewed

- DeepLink.swift is a type alias to AccountModels plus a main-actor NavigationRoute conversion; URL parsing/identity logic is already owned by AccountModels.
- Keychain.swift is a main-actor Factory binding to the CredentialStore port; the SDK secure-storage implementation stays in SwiftfinCredentials.
- UserSessionService.swift is the app's actor-isolated lifecycle composition protocol and empty defaults; it contains no native resource implementation.
- ServerSocketManager.swift retains exact weak UserSession binding and presentation publishers. Native sessions/reconnection/subscription leases delegate to Networking. Its tasks consume checked values on the main actor, capture the manager weakly and cancel at stop/isolated deinit.
- MediaPlayerSupplement.swift retains platform overlay type erasure, labels/presentation style and identity equality. PlaybackRateMediaPlayerSupplement.swift retains UI increment/decrement actions through the app manager. MediaPeopleSupplement.swift contains only immutable people input and platform poster/row layout; role facts already delegate to ItemMetadata.
- MediaChaptersSupplement.swift now retains chapter layout/seek actions and prepares the PlaybackPreviews selection snapshot once. Its thin index-to-ID adapter preserves payload order and all original missing/first/last/unsorted/duplicate behavior, independently checked against 8,613 original decisions. Episode queue task ownership delegates to AsyncStreams as described below.

## Completion evidence still required

- Classify all retained sources, with actual body/consumer evidence for every retained or extracted responsibility.
- Review the complete public API/consumer graph and actor/resource lifetime contracts.
- Complete current whole-graph navigation, restricted-account playback/recovery and renderer/output cleanup after the human lifts the simulator hold.

Physical-device/live CloudKit/server boot/App Store release gates remain separate. Nothing in this review authorizes RAID access, household account/catalog changes, or resuming simulator testing.


## Chapter and episode queue body review

MediaChaptersSupplement retains immutable chapter/poster payloads, the existing hash-based ID, selected/initial IDs, SwiftUI layouts/focus, localized text and manager seek/play actions. ChapterSelectionTimeline owns the only removed pure selection algorithm. Its prepared ordered optional times are immutable and checked Sendable. The entire extension containing platform overlay/rows/buttons compares byte-identical with the original source at 453c223f. It is retained presentation/composition.

EpisodeMediaPlayerQueue's remaining head composes seasonal paging models, a weak player manager, its independent Published subscription, adjacency UI publication and SDK-value playback providers. LatestRequest owns replaceable task/generation/cancellation/release; MediaCatalog owns the bound adjacency read. The app captures client/item before asynchronous execution, keeps the binding check, and receives values weakly on the main actor. Cancellation clears visible adjacency before a new request. Releasing the request owner cancels without waiting for a noncooperating operation. The complete seasonal/episode overlay extension and both bitrate/reset/modifier resolver bodies compare byte-identical with the original source. These retained bodies are platform UI and playback composition, rather than a new public library exposing app player objects.

Further source inspection identified specific remaining behavior to review/extract or repair:

- MediaInfoSupplement.updateCurrentProgram now delegates the captured delay and bound item read to ItemMetadata. Cancellation propagates before IO; app publication requires the same account/item/program. Its remaining body is presentation/composition.
- PlaybackInformationProvider now delegates selection to ServerOperations and task/generation/release to LatestRequest. Private account/transport snapshots, account/connection switching, explicit main delivery and weak binding-checked UI publication remain composition.
- EPGSupplement now delegates strict recency to Time. Its view-state guards, selected channel, refresh forwarding and playback-provider selection remain UI/presentation composition.

These candidates and the complete 668-file/public-interface consumer classification remain open. Search/import counts, generated inventories and passing synthetic tests do not close the whole-client review or held runtime acceptance.


## Explicit file-body and current interface review

The [hashed ledger](source-review-ledger.json) covers every current app Swift path and keeps unreviewed files pending. This pass reviews all 28 Shared/Objects/Libraries bodies plus five chapter/episode/guide/info/session overlays. Twenty-five library adapters retain display/selected-setting/parent/first-page/view-model/query-port composition and UI. Three remain mixed: NextUp notification membership/minimum-interval selection, Resume played/progress membership and media-kind mapping, and UserView artwork/query classification. These are open ownership decisions, with exact current source hashes and per-file reasons. Thirty retained files are recorded; 635 further files are pending. Earlier prose reviews are not silently counted as current full-body classification.

The current three interface reviews record exact source hashes, symbols, consumers and policy limits for Time recency, bound delayed ItemMetadata reads and ServerOperations session preference. They do not classify the remaining public graph. Program/date/session originals were independently executed with fixed capture-only clocks; all valid original outputs match. Invalid deadlines now throw a typed error instead of trapping Duration conversion. The item read retains plugin-compatible ID behavior and exact account/transport cancellation gates. App guards retain current item/program before publication.

Playback-session composition captures one account/transport/device snapshot per stream binding. Account and connection notifications rebuild it. Switch-to-latest and empty initial receipts clear old streams; explicit main scheduling precedes LatestRequest selection and weak current-binding publication. The native async-stream relay source was reviewed: its task/subject delivery is on the main actor, and socket-driver generation guards precede payload emission. This source evidence does not prove current GUI/native callback behavior, which remains held.
