# Retained application responsibility review

The application is intended to retain composition and platform presentation. This is a source-reviewed ledger, not an automatic approval of files based on their folder, filename or import count. The full-client refactor remains active. Live simulator/server activity is held by the human. Current ledger:396 retained, 14 mixed and 255 pending among 665 app files;33 scoped interface reviews.

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

## Library adapters and retained object review

The current ledger explicitly reviews all 28 Shared/Objects/Libraries bodies. Next Up and Resume no longer choose policy intervals or membership precedence; UserMediaState returns immutable actions and the app applies them. Catalog owns ordered resume-kind projection and user-view/favorites/live-TV artwork query classification, retaining the exact parent/favorite/type semantics captured before extraction. No new library or dependency edge was introduced.

UserView retains full grid/list layout, routes, selected random-image setting and app Poster image presentation. Its catalog receives an exact weak manager/session/client predicate; account/connection events clear stale view images and restart cancellable tasks. Post-read and post-projection guards reject obsolete output. This does not classify general Poster internals, which remain separately pending.

Thirty-two additional Shared/Objects bodies were inspected. Thirty presentation aliases/protocols/enums/configurations/style adapters are retained with individual reasons in the JSON ledger. LocalUserAccessPolicy's evaluated PIN token and PlaybackCapabilities' native hardware probing remain mixed, with explicit next ownership questions rather than blanket approval. Current totals are 63 retained, two mixed and 603 pending, plus five limited interface/consumer reviews.

The new fixture independently executes original Next Up/Resume callback bodies, media-kind projection and artwork scope classification. Adjacent native tests add exact SDK query fields and cancellation/binding boundaries. Actual view lifecycle, rendered images and current authenticated playback remain held. Whole-source or whole-public-API completion is unproven.

## Evaluated prompt values, native probes and small component review

The app-local evaluated-policy marker/PIN result moved into AccountAccess with an explicit public initializer and no storage/authorization authority. Its consumers retain exact original PIN comparison and save/hint bodies. WithLocalUserAuthentication is retained SwiftUI request/sheet/error/cancellation composition; its PIN length predicate delegates to AccountAccess and device authentication delegates to Permissions. Empty retains only a sentinel conformance to the owned marker. No PIN normalization/digit restriction or credential/policy mutation was added.

PlaybackCapabilities is retained selected-preference/localized-label/profile-snapshot composition. NativePlayback's private probes hide AVPlayer/Metal/VideoToolbox and CoreMedia constants; the injected reader preserves lazy/current reads and exposes only semantic codec/Bool/String values. Complete app property/profile body comparison proves the source transformation, while native contracts use synthetic readers. Real hardware/GUI/native output remains held.

Nineteen additional Shared/Components bodies were inspected. Eighteen remain specific platform styling/layout/focus/action/image-source composition, with dependencies explicitly left to their separate reviews. FastSVGView still performs native SVGKit parsing/view construction and force unwraps its result; its mixed record names dependency placement and malformed/changed-data handling as next work. Current counts are 83 retained, one mixed, 583 pending and seven limited API/consumer reviews. These counts do not prove whole-graph completion.


## SVG transfer and small presentation bodies

FastSVGView is now retained presentation: it delegates native parse/render/retirement to ImageProcessing, preserving exact original style/priorities after explicit update/dismantle additions. Fourteen geometry/formatting/color/image/URL extension bodies and fifteen object bodies were inspected in full. Their individual ledger reasons retain 28 specific presentation/composition adapters; the SelectUserServerSelection body remains mixed because installed raw identity and first-ID lookup belong with immutable account selection while Storable conformance is application composition. No folder/import-based blanket classification was added.

Current totals are 667 app files: 112 retained, one mixed and 554 pending. Nine scoped interface/consumer entries include the internal SVG controller and public native surface; they do not close the complete public graph. Six fake-render contracts prove reuse, invalid replacement, empty input, reset/reentrancy and release, while compile-only platform checks prove linkage. Actual parser/drawing and UI lifecycle remain held.


## Account selection and 113 additional source bodies

SelectUserServerSelection is a retained app alias of the AccountModels-owned checked-Sendable value. StoredValues owns serialization conformance; original consumer bodies/keys/suite declarations are exact. Independent original captures preserve the reserved sentinel collision, raw/JSON/defaults shape and first exact record in duplicate order. The fixture is packaged for native and platform test hosts; current platform proof is compile/copy only.

The review inspected all 47 selected object bodies, 42 SDK adapters and 24 platform UI/SDK composition bodies. Each of the 102 retained and 11 mixed dispositions records a concrete reason and current hash. Among the mixed bodies, OnFinalDisappearModifier calls an arbitrary callback from unisolated deinit; its native-player consumer calls main-actor manager.stop. ScrollViewOffsetModifier replaces a borrowed delegate without explicit restoration/rebinding ownership. These source findings are actionable follow-ups, not observed runtime failures or completed repairs. Reusable request/value classifications remain with their named existing-owner candidates.

Current source totals are 667: 215 retained, 11 mixed, 441 pending. Eleven interface/consumer entries remain limited to their recorded scopes. The new six synthetic/native contracts and final platform compiles pass, while full UI/native teardown/streaming acceptance remains held.


## Final-view, jump and offset review (2026-10-07)

OnFinalDisappearModifier retains only SwiftUI lifetime placement and delegates final main-actor delivery to UIState. JumpProgressObserver is a spelling-only alias; original count/direction/reset/deadline behavior belongs to UIState and all five consumers remain unchanged. ScrollViewOffsetModifier retains introspection and its latest Binding; Scrolling privately owns native observation, weak target identity, revisions and retirement without replacing delegates. NativeVideoPlayer's complete unchanged body is retained composition/presentation, with its native surface and manager operations delegated.

Twenty additional complete bodies were read with per-file reasons in the hashed ledger. Nineteen retain app routes, Factory composition, permission labels, form bindings, button/style/typography presentation, application-only Spotlight metadata, error values or environment wrappers. This is source inspection, not promotion from folder/import patterns. EPGScrollState remains mixed: its offset subject and strict greater-than-0.5 threshold need existing scrolling ownership and actor/consumer verification. Remaining mixed files are ImageBlurHashes, PlayerStateInfo, SpecialFeatureType, TaskTriggerInfo, LibraryParent, MetadataRefreshType, ServerLogType and TextTransferable.

The authoritative ledger records 238 retained, nine mixed and 420 pending, plus fifteen limited interface/consumer reviews. Native52, compile-only120/46/65 and preservation393 pass; actual UI/native callback/teardown behavior remains held. Full source/API review and runtime acceptance remain required for the original goal.


## Nine resolved responsibilities and administrative review (2026-10-07)

The prior nine mixed entries are resolved into existing owners. The app blurhash implementation is removed; its existing image-source consumer already imports metadata and remains exact. Remaining wrappers preserve optional tick projection, localized extra/log/refresh labels, generic parent identity, trigger constructor spelling, guide state spelling and native ShareLink presentation. The captured old defaults, ordering, Unicode/anchoring, rounding, offset thresholds/nonfinite behavior and UTF-8 filenames/bytes are preserved by adjacent native contracts.

All twelve administrative view-model bodies were read, totaling 1,186 lines. Nine are retained main-actor screen/action/observer composition with specific reasons in the ledger. APIKeysViewModel remains mixed because replacement revoke/create/reload sequencing and intermediate partial-failure UI ordering still live in the app. ActiveSessionsViewModel queues socket receipts without an explicit account generation; ServerTasksViewModel also drops nil session roots with compactMap and queues updates without such a guard. Native upstream retirement alone does not prove queued stale receipts rejected. These three need owned sequencing/lease contracts and scoped integration before completion.

The authoritative hashed ledger records 255 retained, three mixed and 408 pending among 666 app Swift files, plus twenty-one scoped interface/consumer reviews. Native53, compile-only121/47/66 and preservation402 pass; source review does not substitute for held GUI, socket/account switching, native callbacks, sharing cleanup or playback acceptance. The original goal remains active.

## Account-scoped administrative screens (2026-10-07, offline)

The three previously mixed complete bodies now retain presentation/composition. APIKeysViewModel delegates compound creation and replacement to ServerOperationsClient, retaining its missing-field error, local revoked-row removal, nil-list behavior and success event. All other command bodies remain unchanged. ActiveSessionsViewModel and ServerTasksViewModel supply emitted account roots and captured transport identity to ScopedPublisher, along with weak current-binding and UI receipts. The emitted value is used because @Published publishes before setting currentSession. Logout explicitly cancels; changed account/connection clears old rows. Pause/filter, ordered observers, category sorting and existing refresh/command bodies are unchanged.

ScopedPublisher privately owns source cancellation, queued generations, executor entry and reentrant retirement. It has no SDK, account/container or settings dependency. Twelve native contracts verify lifetime and ordering, including foreign Combine emission. Ten key-operation contracts verify exact routes/methods/name, sorting, nil results, partial failures and cancellation/expired-account boundaries. The original nil-root subscription defect has separate failing reproduction evidence. The ledger records 258 retained/408 pending and 23 scoped API reviews; this does not approve the pending files or establish actual socket/GUI acceptance. Live testing remains held.

## Account composition and socket command review (2026-10-07, offline)

Fifteen whole sources were read and hashed. UserSession/resource and feature-owner adapters, socket bridging, connection resolution, cache-index observations, the base view model, notification names/native values, storage opening, application framework configuration and diagnostic presentation remain app composition. NetworkLogger now delegates its reusable DTO redaction to Networking. Remote SDK command interpretation belongs to PlaybackPreparation; the iOS host retains native player controls, preference values and navigation while composing scoped/lazy async owners. All tvOS remote subscriptions remain disabled.

UserSessionManager remains mixed because its delayed mediaPlayerManagerPublisher assignment needs a downstream identity/generation and operation audit. ServerState/UserState extensions remain mixed because replacement account/cache writes after metadata reads belong to coherent AccountStore persistence/merge ownership. These are explicit findings, not approvals based on folder/import counts. Current ledger: 270 retained, three mixed and 393 pending; 26 scoped interface reviews. Native tests and compilation do not establish actual socket, navigation, player or account-switch behavior under the continuing runtime hold.


## Metadata adapters and further presentation review (2026-10-07, offline)

ServerState/UserState retain reader/settings/version/image composition after metadata writes moved to AccountStore, with explicit post-await checks before commit. Complete server/user key adapters preserve current-session app settings while delegating account/cache addresses. NavigationRoute+Media and VideoPlayer/updated NativeVideoPlayer retain route/proxy/safe-area/scrub/control presentation, with exact-origin factory resets.

Forty unchanged complete presentation bodies were reviewed with individual ledger reasons: metadata/policy edit sections, item actions/labels, country/rating pickers, guide date/ruler geometry, letter focus/callout, poster indicators, slider color/progress styles and toolbar controls. UI binding/layout/interaction remains in the app; providers own catalog/metadata/queue/native operations. These classifications do not approve whole provider bodies or claim OS callbacks tested.

UserSessionManager's delayed player assignment is resolved but deep-link/authentication/sign-in/foreground inter-await sequencing and shared freshness remain mixed. The entire MediaPlayerManager body is now reviewed/mixed: async start/playNewItem/rebuild publication and queue/provider/supplement responsibility extraction still require work. Reading or compiling does not establish those operations safe.


Native sweep **56** passes **831** contracts (**802** Swift Testing and **29** XCTest), eight generator checks and three runtime helpers. Unchanged macro inputs retain **18** passing contracts. Boundary **53** and analyzer **35** pass, including a new explicit network-API ban in AccountStore while permitting metadata types and their Defaults bridge. Compile-only tvOS Debug **125**, tvOS Release **50** and iOS Release **69** pass without owned Swift/generated-macro diagnostics.

Accepted preservation audit **434** verifies **1,237** frozen inputs, both original forty-revision SDK graphs and clean tracked checkouts, paid-team/signing/persistence configuration, all five protected local files and equal cancellation-restored progress. Simulator cloud transport remains NO. Metadata426's no-write assertion confused registered defaults with persistent data; it now checks persistent domains. Debug124's missing test-runner link was fixed by explicitly linking AccountStore. The import-only boundary expectation was revised to permit storage types while rejecting request APIs. Audit433's method-range selector was corrected. Failed attempts remain recorded.

**Simulator automation, installation, launches, playback and server-facing diagnostics remain stopped until the human explicitly resumes them.** No live acceptance or server account/catalog/configuration/RAID change occurred. The ledger is **316 retained / 2 mixed / 348 pending / 29 scoped API reviews** among666 app sources. Full items1/2 remain active; physical-device/live CloudKit and independently managed server/release gates remain separate.


## Further model/provider source review (2026-10-07, offline)

Twenty complete sources were read and individually classified. Sixteen retain editor labels/input projections, supplied paging/group composition, view context/pill presentation, the main-actor queue port/type erasure and bound password/Quick Connect/filter/image operations. Four explicit mixed entries remain: LocalUserSecurityViewModel and SelectUserViewModel duplicate local PIN/security sequencing; BaseFetchViewModel needs an explicit post-await publication/macro lifecycle contract; IdentifyItemViewModel needs query generation and apply/reload/event sequencing review. These findings do not establish runtime defects without further evidence. The ledger records exact hashes and reasons for every body.


## Scoped session metadata refresh (2026-10-07, offline)

The existing Sessions library now owns SessionMetadataRefresh, using the existing AsyncStreams LatestRequest. This adds one one-way local edge, Sessions to AsyncStreams, and keeps the graph at 53 libraries. Success freshness is process-local, bounded and keyed by immutable server/user/URL values; the old unscoped timestamp no longer controls scheduling. The compatibility timestamp is still written after success. Restart resets freshness deliberately, since a historic global stamp cannot identify the account it covered.

The main-actor API coalesces a current scope, supports forced refresh and owns cancellation/replacement/weak lifetime. Sendable clock, currentness and pre-commit checkpoints guard obsolete noncooperating returns and reentrant callbacks. Fourteen synthetic contracts cover strict age/rollback, per-account isolation, capacity, partial failure, owner release, A-B-A, coalescing and cancellation reentry. Already committed effects are not undone; callers must checkpoint immediately before subsequent local effects.

UserSessionManager captures the exact session/transport before scheduling and cancels refresh at session-replacement entry and publication. Server/user adapters validate before their reads and after bound-reader verification immediately before AccountStore commit. Higher-level deep-link/auth/sign-in/foreground intent sequencing remains mixed and unapproved.

Native sweep 57 passes 845 contracts (816 Swift Testing and 29 XCTest), eight generator checks and three runtime helpers. Unchanged macro inputs retain 18 passing contracts. All 53 library boundaries and 35 analyzer tests pass. Compile-only tvOS Debug 126, tvOS Release 51 and iOS Release 70 pass without owned Swift/generated-macro diagnostics. Preservation audit 449 verifies 1,239 frozen inputs, both original forty-revision SDK graphs and clean tracked checkouts, paid-team/signing/persistence settings, all five protected local files and equal cancellation-restored progress. Debug cloud transport stays NO. The expiry 441 and reentrant-coalescing 443 failures remain separate evidence covered by passing regressions.

Live simulator automation, installation, launches, playback and server-facing diagnostics remain stopped until explicit human resumption. These checks establish synthetic contracts and compilation, not current GUI/account-switch/playback acceptance. The hashed ledger contains 666 app files:332 retained, six mixed and 328 pending, plus 30 scoped interface/consumer reviews. Full items 1/2 remain active; physical-device/live CloudKit and separate server/release gates stay deferred.

## Local security policy and PIN ownership (2026-10-07, offline)

The existing AccountStore now owns exact local PIN comparison and credential-first security transitions. matchesPIN(_:userID:allowMissing:) denies a missing credential by default; only old-PIN verification in the security editor explicitly permits absence. Existing String equality preserves case, whitespace, empty values and Unicode equivalence. Read errors propagate. setLocalSecurity(userID:policy:pin:hint:) writes a required PIN or removes it for either other policy, then uses the installed policy and hint setters. A credential failure prevents either settings write; settings retain their existing nontransactional/nonthrowing storage semantics.

LocalUserSecurityViewModel and SelectUserViewModel now retain localized errors, UI events and authenticated-user/account presentation while delegating credential comparison/security sequencing. UserSessionManager also delegates evaluated-PIN validation, retaining local prompting and its still-unresolved higher-level session intent ordering. Factory composition supplies the same singleton credential implementation; no credential sync, format restriction, namespace/key or account scope changed. No new package, production edge or external version was added.

Nine adjacent native contracts use a fake credential port and isolated temporary account storage, and also compile in the actual tvOS validation target. They verify missing-PIN differences, exact comparison, read/write/removal errors, credential-before-settings observation, empty PINs and sibling/token/parent-PIN preservation. Twenty-eight further unchanged presentation bodies were read and individually recorded with exact hashes and specific reasons.

The four mixed bodies remain UserSessionManager, MediaPlayerManager, BaseFetchViewModel and IdentifyItemViewModel. Source inspection of the pinned StatefulMacro confirms that its cancellation check follows actuallyRun; it cannot prevent a value assignment inside a suspended registered handler. Generic refresh publication and query/update sequencing still need explicit owned contracts and regression evidence. These findings do not approve the 300 pending files or establish current runtime behavior.

Native sweep 58 passes 854 contracts (825 Swift Testing and 29 XCTest), eight generator checks and three runtime helpers. Unchanged macro inputs retain 18 passing contracts. All 53 library boundaries and 35 analyzer tests pass. Compile-only tvOS Debug 127, tvOS Release 52 and iOS Release 71 pass without owned Swift/generated-macro diagnostics. Preservation audit 455 verifies 1,240 frozen inputs, both original forty-revision SDK graphs and clean tracked checkouts, paid-team/signing/persistence settings, five protected local files and equal cancellation-restored progress. Debug cloud transport remains NO.

Live simulator automation, installation, launches, playback and server-facing diagnostics remain held until explicit human resumption. No real credential store, OS permission prompt or server account/catalog/configuration/RAID operation was used by this change. These tests establish synthetic credential/storage behavior and compilation, not current GUI authentication or playback acceptance. The ledger records 666 app files:362 retained, four mixed and 300 pending, with 30 scoped interface/consumer reviews. The complete items 1/2 objective remains active.

## Identification and twelve further model/provider bodies (2026-10-07, offline)

IdentifyItemViewModel now retains only Stateful/Combine presentation and caller task/error adaptation; publication relevance belongs to AsyncStreams and captured apply/reload belongs to ItemMetadata. BaseFetchViewModel had no consumers in the full code/configuration scan and was removed. Its generic fatalError abstraction was not migrated into a new unused package.

ContentGroupViewModel retains supplied refresh/group UI composition after complete review of ContentRefreshCoordinator guards; LiveTVGroupProvider retains static labels/icons/routes and supplied query rails. Ten newly mixed bodies are ConnectToServerViewModel (admission writes/receipts), EPGViewModel (range/calendar/channel grouping and timer rebasing), ItemImageViewModel (mutate/reload/publication), ItemComponentEditorViewModel (queued search/update/event sequencing), ItemEditorViewModel (delayed refresh/update publication), ItemSubtitlesViewModel (mutable search inputs and command/refresh publication), RecordingTimerViewModel (snapshot mutation/reload/events), SearchViewModel (debounced filter intent and separately tasked nested refresh), ServerConnectionViewModel (edited snapshot/test/admission receipts) and UserSignInViewModel (post-auth credential/account admission and strict PIN validation). These are explicit source findings requiring coherent ownership and lifecycle work; no runtime defect is inferred solely from inspection.

The ledger now contains 665 hashed app files:365 retained, 12 mixed and 288 pending, plus 32 scoped interface reviews. Existing UserSessionManager and MediaPlayerManager remain mixed. Full provider/API/actor/bootstrap review is unfinished. The extra mixed entries record broader inspection rather than blanket approval of ViewModels.

Native sweep 59 passes 870 contracts (841 Swift Testing and 29 XCTest), eight generator checks and three helper suites. The final cancellation adapter changes only app source; library/test/helper hashes are identical to that native run. Unchanged owned macro inputs retain 18 passing contracts. Boundary 53 and analyzer 35 pass. Compile-only tvOS Debug 129, tvOS Release 54 and iOS Release 73 pass without owned Swift/generated-macro diagnostics. Audit 465 verifies 1,242 frozen inputs, both original forty-revision SDK graphs and clean tracked checkouts, paid-team/signing/persistence settings, five protected local files and equal cancellation-restored progress; Debug cloud transport remains NO.

Simulator automation, installation, launches, playback and server-facing diagnostics remain stopped until explicit human resumption. Cancelled acceptance 79 remains cancelled. Synthetic contracts and compilation do not establish current GUI debounce, macro background-state lifetime, authentication or playback acceptance. Full items 1/2 remain active; physical-device/live CloudKit and separately managed server/release gates remain deferred.

## Twenty-eight further presentation and DTO adapters (2026-10-07, offline)

Twenty-eight complete unchanged bodies (2,350 lines) are now individually classified with exact source hashes and specific retention reasons. They include measured/variadic layouts, retry and form presentation, culture and playback-value pickers, poster/focus/image wrappers, truncation/selection, profile-image notification presentation, native navigation-bar appearance and eight DTO display/image/transfer/choice adapters. Each invokes supplied actions or existing data/resource owners; underlying provider bodies are not approved by their UI callers.

Reading the actual app ItemFilter protocol corrected the provisional trait finding: it extends Displayable to support UI choice/type erasure; it is not a reusable query protocol. Its raw-value witnesses preserve the existing trusted-choice contract. Filters already owns AnyItemFilter and query evaluation, so no extra package or migration is justified for this display adapter.

The ledger now records 665 app files:393 retained, 12 mixed and 260 pending, with 32 scoped interface/consumer reviews. No compiler input changed after identification checkpoint129/54/73:the same 1,242 hashes retain native59's870 contracts, macro18, boundary53/analyzer35 and three clean compile-only builds. These classifications establish source ownership, not correctness for every unsupported input or actual native layout/focus/notification lifetime. Existing TODOs and native visual acceptance remain open where recorded.

Simulator automation, installation, launches, playback and server-facing diagnostics remain stopped until explicit human resumption. The full items1/2 source/API/actor and whole-graph acceptance goal remains active. Physical-device/live CloudKit and separate server/release gates stay deferred.

## Component editor and platform/child host bodies (2026-10-07, offline)

The complete generic component editor and all four genre/studio/people/tag ports were read. The editor now retains caller task/error adaptation, generic input/UI state, debounced presentation and notification/event/advisory composition. Captured update/reload belongs to ItemMetadata; weak publication relevance belongs to AsyncStreams. Library source/test/consumer review is scoped and does not approve the remainder of the metadata client graph.

Five previously pending complete bodies are now recorded. iOS/tvOS SwiftfinApp retains configure/appearance/root/auth presentation and conditional silent push registration; provider/SDK/cloud startup delivery is still separately reviewed or deferred. KidsAccountAdapter is mixed because parentPIN masks credential read failure as absence, and its deferred storage/activation callbacks require an end-to-end admission-intent audit with KidsApplication.signIn. KidsPlaybackAdapter is mixed because account capture, awaited metadata, resume DTO projection and provider/manager publication must be reviewed as one bound preparation flow. KidsMediaProgressObserver is mixed because its initial sender comes from current ViewModel session while item identity comes from a supplied item; exact construction binding, static ordering link and sample/terminal subscription lifetime remain unapproved.

These findings come from the actual host bodies, KidsAccountHost/KidsAuthenticatedAccount, the KidsApplication signIn consumer and reporting port. They do not prove a live failure or automatically approve any called provider. Current ledger:665 files,396 retained/14 mixed/255 pending;33 scoped API reviews. Full source/API/actor/bootstrap and held runtime acceptance remain unfinished.

Native sweep 60 passes 877 contracts (848 Swift Testing and 29 XCTest), eight generator checks and three helper suites. Metadata476 independently passes 63 contracts, including seven new fake-sender update/reload checks. Unchanged owned macro inputs retain 18 passing contracts. All 53 library boundaries and 35 analyzer tests pass. Compile-only tvOS Debug131, tvOS Release56 and iOS Release75 pass without owned Swift/generated-macro diagnostics. Preservation audit485 verifies 1,243 frozen compiler inputs, both original forty-revision SDK graphs and clean tracked checkouts, paid-team/signing/persistence settings, five protected local files and equal cancellation-restored progress. Debug cloud transport remains NO.

Simulator automation, installation, launches, playback and server-facing diagnostics remain stopped until explicit human resumption. Cancelled acceptance79 remains cancelled. These checks prove synthetic contracts, source review and compilation; actual Combine debounce, Stateful background-state lifetime, GUI editing/authentication/native playback and full whole-graph acceptance remain held. No real credential access, native permission prompt, household-server request or RAID operation was performed. The complete items1/2 objective remains active; physical-device/live CloudKit and separate server/release gates remain deferred.

The final input-handler correction uses a quiet task-cancellation guard in both component and identification search submission. Inspection of the pinned StatefulMacro confirms that a thrown cancellation can reach its error-publication path before the post-handler cancelled-task check. Library/test/helper source hashes are identical to native60; only these two app adapters changed afterward. Earlier Debug130/Release55/iOS74 compile the preceding adapter; final131/56/75 cover the corrected guard. Actual macro/UI runtime acceptance remains held.
