# Swift 6 ownership modernization

This pass makes UI, saved-account, playback, and observation ownership explicit before extracting the remaining monolith into Swift packages. It changes only the app targets' language setting; dependencies keep their declared package language modes. The default actor isolation remains `nonisolated`, with explicit `@MainActor` declarations for UI and session work.

## Changes

- Saved user sessions, their factories, login/PIN callbacks, route content, gesture coordinators, preview image providers, and dynamic user-specific playback profiles are owned by the main actor. Pure identity hashing and immutable defaults remain usable outside it.
- Isolated protocol conformances retain the actor boundary where a legacy library or supplement holds a UI view model. A short-lived actor-owned refresh batch preserves parallel library refresh without transferring those existential values to child tasks.
- The settings override table stores immutable Swift values in `Synchronization.Mutex`. Foundation bridging happens after lookup, so an arbitrary mutable `Any` is never shared by the table. The one existing continuation-resumption lock has a narrowly documented `@unchecked Sendable` conformance; the lock protects its only mutable field.
- `PokeIntervalTimer` uses a cancellable one-shot task with a weak owner. Replacement, Stop, delivery, and destruction occur on the same actor. A pending deadline no longer retains the dismissed player or toast through a dispatch-work-item cycle.
- Stored-value observation inherits its owner's actor. SQL observation announces changes to the existing store instead of decoding and writing an observed value back into it.
- Artwork prefetch crosses child tasks using a Sendable model reference and immutable item metadata; image creation stays on the model's actor.
- Status screen actions use explicit `action:` labels. Swift 6 forward matching bound an ambiguous trailing closure to the optional parent callback, displaying a spinner and Parents button instead of Retry. The remote recovery regression caught this real UI behavior; failed trials are retained. The additional assertion now tests the visible, usable Retry control instead of absence of a parent button in the underlying browse toolbar. All status-action call sites now name the intended callback.
- The iOS Release identifier and Spotlight application identity now use `com.kridsdale.JellyfinPlayer` and the configured KidsJellyFin display name.

System remote commands copy only immutable event values into a main-actor task and reject obsolete audio leases. AVPlayer observations and seek completions cross to the actor and reject replaced playback generations; delayed transport work is cancelled on dismissal. These SDK paths compile, but the kids simulator stream uses VLC rather than establishing full AVPlayer behavior.

These changes do not relax account/library authorization, add media, prefetch full video, migrate the storage schema, or write to the server's RAID.

## Verification

`sh Scripts/Kids/test_runtime.sh` compiles the actual production utilities in Swift 6 on macOS and exercises their behavior:

- Boolean/string/integer/double overrides and conversions, removal, preservation of underlying saved values, and 64 concurrent independent writers performing 6,400 updates.
- Replacement of pending deadlines, Stop and reuse, actor-isolated delivery, releasing an owner with a pending 60-second timer while retaining its subscriber, and subscriber cancellation.
- Bitrate calculation from the actual received payload and monotonic fractional duration, lower/upper bounds and rejection of empty or invalid measurements. This replaces wall-clock timing and an assumption that requested bytes equal returned bytes; it adds no request or cache.

The tvOS Debug app build with `KIDS_SWIFT_LANGUAGE_VERSION=6` passed in `/private/tmp/kids-swift6-explicit-14.log`. The latest iOS Release build passed for both arm64 and x86_64 in `/private/tmp/kids-swift6-ios-release-06.log`, including the SDK callback ownership and bandwidth-measurement changes. The shared app configuration now selects Swift 6. The first real acceptance run failed: synchronous legacy `@Function` handlers executed off the main actor after StatefulMacro erased closure isolation in its registry. Pause/play then trapped in main-actor Combine consumers. App handlers now use an explicit asynchronous method boundary and actor preconditions, so generated `await` calls hop to the owner before accessing state. All nine synchronous app handlers were covered, including connection monitoring and sign-in. No dependency checkout is patched. The combined build compiled and passed 21 of 22 acceptance checks: all 16 navigation checks and five real-account playback methods. Its failed-stream Retry kept the right item but lost the initial checkpoint because the controller had not initialized its displayed time before a failed open. The controller now retains the requested position until an accepted native clock exists. The failed result is retained in `Kids-Swift6-Acceptance-05.xcresult`; the repaired exact-item/checkpoint Retry passed in `Kids-Swift6-Recovery-06.xcresult` (48.059 s). Genuine EOF/countdown/next playback passed in `Kids-Swift6-Natural-07.xcresult` (60.716 s); the genuine second EOF stopped at the persisted cap in `Kids-Swift6-Session-Cap-08.xcresult` (47.425 s). The complete original simulator progress was restored through the SwiftData SDK and compared equal. These are separate results, not one all-green combined run. The final native package rerun passed 69 core/HTTP tests plus 23 persistence tests; the profiling analyzer passed ten tests and App Store metadata tooling passed six. Runtime helper suites passed against actual production code.

An independent, finite server observer captured 239 samples with zero errors. The same anonymous restricted-account session remained present across six consecutive empty NowPlaying samples between two approved H264/AAC streams, then three empty samples after the second stream. All 30 sampled active states were DirectPlay; maximum concurrency was one. A large forward position jump is recorded separately and is not proof of continuous playback. The client tests establish actual frames, clocks and EOF behavior; server sampling corroborates session cleanup. RAID write denial was checked at both ends and the observer logged out. No server configuration or media files changed.

## Compatibility and deferred acceptance

The build retains existing compatibility annotations for third-party SDKs. Remaining inherited Binding, macro, UserDefaults, HostingController, and SDK isolation warnings require separate review; a successful Swift 6 build does not mean the entire dependency graph is free of concurrency warnings.

Apple accepted the team API key, but no physical tvOS device was available for the development profile. The human explicitly deferred physical-device installation and live CloudKit transport testing. Local SwiftData tests, ad-hoc simulator signing, and selecting the paid team do not establish signed-device or cross-device iCloud success.

The next goal remains the [Swift package responsibility refactor](next-goal.md), after the current engineering work finishes.

## Session/transport/schema checkpoint (2026-10-06)

The session lifecycle and HTTP/socket implementations now have independent owner libraries, with a separate checked Combine/async-stream subscription bridge. Explicit schema construction actors remove 23 inherited storage/fixture compatibility imports; app imports and isolated SwiftUI/Identifiable/native delegate conformances are corrected. A private startup-only SDK logger setter is the retained interoperability exception, guarded against repeated installation and writes after database construction. Existing unchecked diagnostics and SDK asynchronous authentication/client lifetime still require the final ownership audit; this checkpoint does not establish full Swift 6 completion.

Debug 54, tvOS Release 07 and iOS Release 19 pass without Swift compiler/generated-macro warnings. Native sweep 16 passes 228, macros 07 pass 18, boundary/analyzer tests pass 27. Integrated acceptance 54 passes all 45 plus separate genuine EOF/next and session-cap gates; complete SDK progress restoration/export equality is true. Normal launch was visually observed on the approved Shows browser. See [current package boundaries and remaining audit](package-refactor.md) for detailed evidence and retained failures.

## Checked diagnostics and immutable transport credentials (2026-10-06)

Owned diagnostic classes no longer opt out of Sendable checking. Their mutable counters, file handle and once/completion state are stored in checked OSAllocatedUnfairLock values; native URLSession metric callbacks record immutable numeric events. Concurrent file-cap contracts verify whole JSON records and sink ordering. Test fixture request/route storage uses checked locks too. No owned production/test @unchecked Sendable declarations remain.

The SDK authentication mutator has been replaced with its exact typed request so credentials never change within an existing JellyfinTransport. Authentication returns a result to account composition. Exact URL/server/user/token replacement constructs a new cached client without changing previous requests. The inherited image cache now runs through SwiftfinImages, whose native callbacks read checked immutable-value identity snapshots without settings access. Debug 57/iOS Release 20 compile without Swift compiler/generated-macro warnings; integrated acceptance 57 passes all 45 checks plus separate genuine EOF/next and session-cap gates with full SDK restoration/export equality. tvOS Release 08 also passes without Swift compiler/generated-macro warnings; a normal restored Debug 57 launch was visually observed on the approved Shows browser without autoplay. The private CoreStore startup import and explicit scheduled UIKit/Combine actor assumptions remain bounded final-audit items. This checkpoint is not full-client completion.


## App action executor rule

StatefulMacro's pinned worker registry erases closure executor annotations. Keep application `@Function` handlers asynchronous in explicitly main-actor-isolated owners: the generated `await` crosses to the owner before UI or session state is touched. A successful build alone does not establish this execution property. This rule was moved here from the declaration-free Utilities.swift compatibility file when the obsolete import stubs were removed.


## Ordered session choices and original-account avatars (2026-10-07, offline)

SwiftfinSessions now owns selection intent before resource replacement. SessionSelectionCoordinator captures a weak, opaque owner/generation request at submission; an unfinished explicit choice blocks passive restoration. Native authentication/stop, persisted selection and routing are injected app callbacks with checks between effects. Added binding validation preserves the original remote-login intent across credential admission and its saved event. Matching abandoned queued work releases restoration; native host disappearance cannot cancel the executing activation that replaces that UI. Cross-owner/replayed/late operations are rejected, including ordinary late authentication failures.

ActiveSessionCoordinator retains its existing publisher adapter and adds checked scoped publication; account identity is Hashable over server/user. The app preserves installed keys, native policy/PIN handling, selected-player composition, metadata scheduling and Factory/UI publication. Deep links activate an exact account pair; native root identity includes both IDs. Already committed synchronous effects, including Published willSet effects, are not rolled back. Real native/auth/restoration acceptance remains held.

Administrative activity details capture original log IDs and account/operation clients. Profile/splash URLs revalidate after resolver reentry and never enable query API credentials. The avatar row uses its original detail-owner source, and success/failure UI publication rechecks account/caller binding.

Native acceptance:47 SwiftfinSessions,31 SwiftfinAccountAccess,27 SwiftfinServerOperations and10 KidsAccounts tests pass (115 total;19 new regressions). Both final platform builds pass:tvOS Debug compile-for-testing and iOS Release with zero owned Swift/generated-macro diagnostics. The53-library boundary check passes. Earlier failed native compiler attempts, the first app builds and the earlier accepted snapshot remain preserved; none are substituted for final acceptance. SDKs retain40 exact original used revisions per graph, Debug cloud transport stays off, protected files are unchanged and saved progress JSONs remain equal.

Twenty-five complete unchanged UI bodies receive individual current-hash reasons covering styles, form/section layout, native permission/PIN presentation, account rows, geometry, media information and choices. Existing native-icon rollback, visual TODOs, geometry-input and environment assumptions are explicit; no native actions were invoked and no provider is approved solely through its UI caller. The665-source ledger now records560 retained,0 mixed,105 pending and58 scoped API reviews. Whole source/API/actor/bootstrap and held runtime acceptance remain unfinished; items1/2 stay active. No new package, graph edge, SDK revision, schema, signing or RAID change.


## Now Playing ownership and administrative UI binding (2026-10-07)

The MainActor NowPlaying registry now revokes authority before potentially reentrant SDK cleanup and captures owner/epoch identity across queued commands, exact-token cleanup and split metadata/play-state writes. Nine new synthetic regressions cover same-controller replay, replacement during installation/removal/enabling/metadata access, orphan cleanup and tvOS interface-handled toggle delivery; all15 native contracts pass. Exact native SDK objects/tokens stay inside the owner. Committed SDK effects are not transactional rollback. The app removes its delayed global MediaPlayer toggle target.

Administrative list operations/avatar resolution retain original bound clients; publication checks surround list/event effects. The obsolete application defaults-swizzling utility is preserved byte-for-byte in isolated test fixtures only;3 runtime helpers pass. Final tvOS Debug compile-for-testing and iOS Release builds pass without owned Swift/generated-macro diagnostics. No runtime simulator or server action is taken. Complete source review still has75 pending and1 mixed body;60 scoped API reviews do not establish whole-graph actor/bootstrap completion. Items1/2 remain active.


## Immutable playback selection boundary (2026-10-07)

PlaybackOptions moves the item-provider source/track/bitrate transition into the existing profile owner. Source DTOs and optional choice values are checked Sendable; a detached-task regression verifies immutable transfer without settings/native/global access. All original transition branches match exactly. All12 native profile tests,53 boundaries and both platform compile-only builds pass without owned Swift/generated-macro diagnostics.

Twenty-nine additional full UI bodies receive native presentation/composition reasons. Existing async TabCoordinator routing contains no suspension or transport; the slider native timer is stopped by its existing representable teardown. This source evidence does not establish native GUI or renderer behavior. The ledger retains46 pending sources and61 scoped API reviews; whole graph and held runtime acceptance remain incomplete. No simulator/server/RAID action occurred, and items1/2 remain active.
