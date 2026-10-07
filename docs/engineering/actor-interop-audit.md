# Actor and SDK interoperability review

This review covers the remaining explicit interoperability exceptions in the owned production sources at the overlay/session checkpoint. The source inventory is a review aid; it is not proof that the complete retained-source/public-API review or current GUI/playback acceptance has finished. Live simulator and server activity remain held by the human.

## Explicit executor bridges

| Source | Execution/lifetime contract reviewed | Verification boundary |
| --- | --- | --- |
| KidsApplication/KidsAppModel.swift, identity subscription | The model and account host are main-actor owners. `receive(on: DispatchQueue.main)` precedes the synchronous `assumeIsolated` update. Immutable account identities are compared before changing the revision, so duplicate identity emissions do not invalidate work. | Source review and Swift 6 compilation. Current GUI identity-switch acceptance is held. |
| KidsArtworkUI/KidsArtworkStore.swift, memory warning | Main-queue delivery precedes the synchronous main-actor trim. The closure captures the store weakly. Invalidation removes the subscription, cancels image flights, clears pixels, and invalidates the byte owner. Memory pressure changes the retention generation rather than triggering a visible grid reload. | Source review and compilation. Current UIKit memory-warning delivery remains unexecuted. |
| SwiftfinUIState/CurrentDate.swift, periodic clock | The private scheduler uses Timer.publish on the main/common run loop and asserts the UI actor before invoking its typed main-actor callback. The observer captures itself weakly and cancels its subscription in isolated deinit. The public wrapper retains the original writable Binding behavior; invalid intervals fall back to one second. | Six fake-scheduler contracts and compilation. Actual native run-loop delivery remains unexecuted under the hold. |
| SwiftfinScrolling/EPGScrollProxy.swift, horizontal and vertical KVO | Main-thread delivery stays synchronous to preserve the reentrancy guard around mirrored content offsets. Foreign-thread callbacks enqueue a main-actor task. Weak scroll/owner captures, connection generation and active-observation membership reject callbacks after disconnect/replacement. Disconnect invalidates both token maps. | Source review and compilation; native geometry contracts do not establish actual UIKit KVO delivery. |
| SwiftfinAsyncStreams/NotificationEvent.swift and app platform key | The raw signal map is created in a nonisolated helper. Only Void crosses main-queue scheduling; the scheduled compactMap explicitly asserts the main actor before invoking the typed reader. App key access/posts are main-actor bound; raw library delivery stays on the posting executor. | Nine native notification contracts include foreign posting, delivery-time reads, pending cancellation and weak-reader release. Actual UIKit status reading remains held. |
| SwiftfinAsyncStreams/LatestRequest.swift and episode queue | Operation and receive are main-actor/Sendable; the task captures its owner weakly across suspension, checks cancellation on both sides, and requires the matching request generation. Completion clears the lease before a reentrant receive. Isolated deinit cancels. App composition retains exact catalog binding, independent player subscription and weak live-manager publication. | Eight fake delayed-operation contracts and compile-only integration; actual player-manager/UI lifecycle remains unexecuted under the hold. |
| Program metadata refresh and playback-info projection | Bound metadata checks precede waiting/IO/return; injected waits are main-actor/Sendable, with cancellation preserved. UI validates the current account/item/program. Session snapshots are checked Sendable, carry exact actor-owned account/transport references, rebuild on root/connection signals and receive explicitly on the main queue. LatestRequest and weak publication recheck binding. | Eight fake delayed-reader contracts, four session policy contracts, original compatibility capture and clean compilation. Actual view-task/socket/main-queue/UI acceptance remains held. |
| Swiftfin tvOS/App/KidsAccountAdapter.swift, identity projection | The adapter owns the main-actor session manager. Main-queue delivery precedes reading session state and constructing a checked-Sendable identity; raw SDK user/session/Keychain types do not cross the KidsAccountHost identity port. | Source review and compilation; current account-switch GUI acceptance is held. |

These are deliberate synchronous bridges at SDK/Combine boundaries, not a blanket replacement for actor hops. Their scheduler/thread guards must remain adjacent to `assumeIsolated`. Moving an upstream publisher or removing its scheduling step requires reviewing the bridge again.

## CoreStore startup compatibility

`SwiftfinStorage/CoreStoreBootstrap.swift` contains the sole owned `@preconcurrency` import. It wraps one write to the pinned CoreStore 9.2.0 global logger, which has no Swift 6 actor annotation. Normal database/schema/operation sources import the SDK with checked concurrency.

`StorageLoggingStartupGate` admits installation only in its fresh phase. The first installation closes that phase; database construction freezes the gate before creating its DataStack. Repeated bootstrap and bootstrap after database construction are rejected. Adjacent native contracts exercise both orderings through an injected writer; they do not mutate the SDK global in their gate tests. The app's configure composition installs the logger before starting storage/cache composition.

The review establishes ownership of this startup write. It does not prove arbitrary third-party initialization outside the owned database path safe. Keep the SDK pinned and review the shim when the SDK gains native concurrency annotations.

## Permission callback ownership

SwiftfinPermissions exposes only checked-Sendable statuses/errors and two main-actor query/request namespaces. Fresh private LAContext/CLLocationManager drivers own each request. Nonisolated callbacks snapshot owned values and communicate through checked lock-backed callback/continuation receipts; terminal completion and cancellation clear the continuation exactly once. Actor cleanup invalidates authentication and clears location callback/delegate leases. No application source imports LocalAuthentication or CoreLocation after extraction; the boundary checker enforces that rule.

Cancellation completes a waiting location request even if the SDK never replies. The public location SDK cannot withdraw an authorization dialog already requested: cleanup means delegate/callback retirement, not dialog dismissal. Native tests use fake drivers and synthetic results, with no actual permission query, location service or biometric session.

## Pure item projections and policy capture

ItemMetadataFacts, ItemMetadataPermissions, CatalogItemState and UserMediaCapabilities are compiler-checked Sendable values. Their stored DTO/time/flag inputs are immutable, and they contain no task, callback, global settings or account lookup. MediaStreamKindPolicy is a stateless raw-value filter. Explicit time inputs avoid repeated wall-clock reads inside a single catalog decision. App wrappers capture current account policy on the main actor before calling the pure metadata/play-button decisions. These policies grant only presentation eligibility; bound mutation owners and Jellyfin retain authorization authority.

## Public native handles and composition

The reviewed native owners retain SDK clients, players, contexts, managers, storage stacks and observer handles privately. JellyfinTransport's public version is an immutable SDK version value; it is not its mutable client. Request/response SDK DTOs remain values at inherited feature boundaries. The mpv owner's explicit semantic-caption interoperability value remains immutable; renderer teardown still needs runtime acceptance because the pinned SDK has no awaited shutdown API.

The platform App initializers call Shared/App/SwiftfinApp+configure.swift. UserSessionRootView composes the KidsAppModel with SwiftfinKidsAccountHost and the playback factory. Settings, selected credentials and approved catalog binding are supplied by these application adapters; reusable owners do not resolve the application Factory container. iOS platform navigation, household signing and iCloud registration remain separate from the tvOS simulator acceptance gate.

## Remaining review work

- Classify every retained application source by UI, composition or behavior; do not infer completion from file counts or a clean import search.
- Review the full public API and consumer graph, not only the native-handle names above.
- CurrentDate observation and EPG grouping now have existing library owners. The [retained-source review](retained-source-review.md) records the extracted item and notification/query policies, inspected service/overlay composition, and remaining chapter-selection/queue/adaptor review.
- Final navigation, decoder/render/output teardown and restricted-account playback/recovery remain held. Compilation and fake-driver tests cannot satisfy those gates.


## Foreign notification callback regression

The first new native run (notification310) terminated with EXC_BREAKPOINT/SIGTRAP. The diagnostic report names dispatch_assert_queue, Swift's executor check and the first closure in NotificationEvent.mainActorPublisher, reached from the foreign synthetic notification post. The map closure had inherited the surrounding main actor before receive(on:main). Moving that raw projection into a nonisolated helper repairs the ownership boundary. The same foreign-posting regression passes in notification311, alongside eight other notification contracts. No unchecked Sendable, unsafe nonisolation or preconcurrency suppression was introduced. The warning about a local weak variable was also removed before the passing run. This native result does not establish UIKit/live-client delivery.

## Library artwork and membership boundaries

LibraryMembershipChange is a checked-Sendable immutable action; the pure UserMediaState rules accept explicit SDK change values and loaded membership. Their callers retain row lookup and UI scheduler/removal execution. LibraryArtworkScope and Catalog's library type/query projections use immutable SDK values without Factory, defaults or SwiftUI dependencies.

UserView captures one main-actor manager/session/transport/user pair before suspension and supplies a weak exact-binding closure to MediaCatalogClient. The existing owner checks that binding before and after each read, including error paths. Grid/list view task identity incorporates root/connection revisions, and corresponding events clear old image state. Final cancellation and exact captured account/transport checks remain beside publication. Fake noncooperating late reads prove discarded obsolete/cancelled results; source review and compile-only checks cover app integration. SwiftUI task cancellation, event/render delivery and actual network/player acceptance remain held.

The expanded source ledger identifies evaluated local-access tokens and native hardware probes as remaining mixed ownership candidates. This audit does not claim all app sources, public consumers or runtime native teardown complete.

## Prompt value and hardware reader transfer

EvaluatedLocalUserAccessPolicy is a public Sendable marker. PinEvaluatedUserAccessPolicy holds immutable raw PIN/hint strings, without Codable/storage/credential or authentication authority. App credential owners continue to validate their stored PIN after the evaluated prompt returns. PIN width remains the exact original extended-grapheme rule. Native tests use synthetic strings only; no real credentials are accessed.

NativePlaybackHardwareReader stores three private checked-Sendable closures. Default closures query platform HDR/GPU/decoder flags lazily and return only Bool/String values; no native handle or mutable SDK instance escapes. Its semantic codec enum maps privately to the original five CoreMedia constants. Injected tests exercise demand/ordering/missing GPU/checked task transfer without actual hardware probes. The app's existing preference and profile expressions remain source-identical after delegation. Hardware changes, SwiftUI prompt delivery and real playback remain runtime-held.

The source/API ledger remains partial. Native SVG parsing/view construction is a newly inspected mixed responsibility and 583 app bodies await review; no complete actor/public-consumer audit is claimed.


## Native SVG ownership (2026-10-07)

SVGRenderState and NativeSVGRenderView are main-actor owners. SVGKit image/parser/fast-view values remain private; the public surface accepts Data and offers native update/clear/intrinsic-size behavior. A synchronous nonescaping factory is never retained. Changed input drops the current object, empty input avoids parsing, and a revision guard rejects reentrant/reset-obsolete results. The UIKit surface owns child mounting/removal; the app forwards representable updates and dismantle. No unchecked Sendable, unsafe nonisolation, preconcurrency suppression or new production-local dependency was introduced.

Six synthetic native contracts cover controller ownership, not SVGKit parsing/drawing. The final compile-only tvOS/iOS checks and frozen-source preservation audit pass; live renderer/callback/teardown acceptance remains held. The source/API ledger is still partial (112 retained, one mixed, 554 pending and nine scoped API reviews); no whole-graph completion is claimed.


## Immutable selection and newly located lifetime risks

ServerSelection has only immutable raw identity and first exact-ID lookup over a supplied sequence. Checked Sendable transfers to a worker executor without settings, SDK clients or native handles. All preserves zero sequence consumption; server selection preserves case/whitespace/empty/Unicode and first-match order. Defaults serialization is in the storage owner, with isolated-suite byte-level compatibility contracts and unchanged app composition. Original RawRepresentable equality and reserved sentinel roundtrip behavior remain exact.

The additional source inspection locates two unresolved interoperability boundaries. OnFinalDisappearModifier stores an arbitrary callback in an unisolated object deinit; NativeVideoPlayer's callback calls manager.stop on the UI actor. Actor-owned final release and a foreign-executor regression are needed before classifying that boundary complete. ScrollViewOffsetModifier installs its own UIScrollView delegate without explicit restoration or native-view rebinding ownership; its existing scrolling owner is the next lifecycle candidate. No actor suppression or speculative UI repair was added while compilation/tests were live.

Final native 51/platform 119/45/64 and frozen audit 379 pass. They establish the recorded offline scopes only. The full source/API/actor review remains partial (215 retained, 11 mixed, 441 pending and eleven API entries), and live simulator/server testing remains stopped until the human resumes it.


## Final-release and borrowed-offset ownership (2026-10-07)

ViewLifetimeObserver stores a main-actor callback and invokes it in isolated deinit. The final strong reference may be dropped on another executor; the runtime delivers release on the owner before the callback. Three native contracts prove no early delivery, exactly-once UI/foreign final release and independent lifetimes. The app StateObject and NativeVideoPlayer stop composition remain unchanged. Actual SwiftUI release timing is runtime-held.

JumpProgressObserver is a main-actor UI owner with a private cancellable and isolated retirement. Its public timer retains the existing expiry consumer; weak callback capture prevents an external timer from retaining the jump owner. Independently captured traces and controlled timer tests preserve count/direction/reset/interval behavior without reading native hardware or contacting a server.

ScrollOffsetLease owns weak target identity, current receipt, observation revision and exactly-once retirement. State changes precede cleanup so reentrant cleanup cannot overwrite a newer connection; post-subscription guards retire obsolete handles. ScrollOffsetObserver privately owns/invalidate its KVO token. The raw callback is created in a nonisolated helper, captures only a checked-Sendable actor-qualified receipt, and stays synchronous under an adjacent main-thread guard; foreign delivery hops to read current geometry on the owner. Raw callback SDK objects and old captured positions are not transferred. The app receiver captures only its Binding, avoiding a whole-modifier/StateObject cycle. Native delegates remain untouched and ordinary disappearance preserves observation lifetime.

Six fake lease contracts pass, including a fail-before/pass-after retirement-reentry regression. Three actual UIKit observation contracts are compiled only. Native52/platform120/46/65 and frozen audit393 pass with the full runtime hold intact. EPGScrollState remains a newly identified unisolated offset-subject candidate. The complete source/public-consumer graph is still partial: 238 retained, nine mixed, 420 pending and fifteen scoped entries; no whole-graph completion is claimed.


## Guide publication, immutable policies and text transfer (2026-10-07)

VisibleScrollOffsetState privately owns CurrentValueSubject on the main actor and exposes only current CGFloat/erased value publication. Original strict greater-than-0.5 filtering and sixteen finite/nonfinite state samples/nine receipts remain exact. Native contracts verify synchronous main-actor callback delivery, cancellation/current replay and foreign-task actor hopping; two actual UI consumers remain unchanged. Native UIKit/layout acceptance remains held.

Refresh selection and log kind are immutable checked-Sendable values. Blurhash, generic-parent/extra, trigger and tick projections operate on supplied scalar/DTO values and do not access accounts, clients, settings or native resources. The original four DTO trigger encodings, three refresh modes, every SDK enum case and signed extreme arithmetic retain exact behavior. Existing SDK/production graph edges stay pinned and unchanged.

TextTransferable's framework representation belongs to Text; its internal writer owns the original atomic UTF-8 temporary export. App code retains only public spelling/ShareLink UI and explicit retroactive immutable DTO conformances. CoreTransferable/SentTransferredFile are deliberate representation values required by the platform protocol, not a public mutable file API. Native export contracts inject private temporary directories and synthetic strings, preserving filenames/bytes/overwrite and native write errors. Actual OS transfer cleanup/share sheets remain runtime-held.

Twelve administrative bodies reveal three incomplete scopes: API-key replacement sequencing with intermediate UI receipts; active-session queued socket callbacks with no explicit account-generation check; and task stream nil-root switching plus queued callbacks. No command or account operation was executed during review. Native53, platform121/47/66 and preservation402 pass, but the complete source/public-consumer review remains partial: 255 retained, three mixed, 408 pending and twenty-one scoped entries.

## Scoped Combine receipts and compound key commands (2026-10-07, offline)

ScopedPublisher is main-actor owned; its raw Combine sink factory is explicitly nonisolated, and only Sendable values cross into queued main-actor delivery. Scope generation is revoked before old cancellation; a candidate is rejected after factory/subscription reentry. Currentness callbacks are checked again for generation changes before publishing or cancelling. Pending callbacks hold the owner weakly; isolated deinit retires the subscription. No unchecked Sendable, unsafe isolation or preconcurrency escape was introduced. Same binding reuses the source and updates its receipt hooks.

The application supplies exact account/transport identities and weak binding/UI callbacks, using the emitted @Published root instead of prematurely reading its setter. Nil roots cancel explicitly. The existing session/task row update and command bodies remain unchanged. ServerOperations key replacement acknowledges successful revocation on the main actor; creation/reload rechecks cancellation/currentness through the same executor afterward. Synthetic contracts cover binding changes and task cancellation in that receipt. Native sweep804 and three clean compile-only builds prove local contracts/type checking; actual account switching, socket delivery and administrative GUI behavior remain held, as does final whole-graph runtime acceptance.

## Command interpretation and cancellation-handler reentry (2026-10-07, offline)

Incoming SDK payloads map through nonisolated pure functions into immutable Sendable intents. The app supplies exact account/transport identities and weak currentness/receipt callbacks to ScopedPublisher. Its tvOS observation method returns before subscriptions. Native metadata/trailer reads use captured feature owners, and publication rechecks binding after async work; actual downstream player assignment/routing remains a mixed-source audit item. No SDK/client or UI object crosses executors through the intent policy.

LatestRequest clears its previous task slot before invoking cancellation handlers, and replacement installs/checks its new generation before cleanup. A reentrant replacement keeps ownership; the obsolete outer call never starts a competitor. The two original failures and repaired native contracts establish this boundary using synthetic handlers on the known main actor. The test-only assumeIsolated calls assert that known cancellation point; no new unchecked/unsafe/preconcurrency production escape was introduced. Current request errors remain logged by the host, while obsolete/cancelled work does not publish. Public actor/API review now includes this owner, the intent policy and pure typed redaction; full graph review and held runtime acceptance remain unfinished.


## Player selection and bound metadata commit (2026-10-07, offline)

Inspected player senders and UIEventPublisher delivery are main-actor synchronous. Removing the extra Task lets UserSessionManager apply source-tagged selection immediately. Reference identity prevents player A's retirement from clearing B; async Stop retires its captured manager. Factory cleanup checks the current factory reference against the originating manager, including native/legacy alert callbacks. Account replacement clears selection. Four synthetic tests prove this selection contract; actual presentation/native lifecycle remains held.

Metadata commits are synchronous in AccountStore after captured URL/token readers recheck binding following await. Exact payload and current-record IDs reject cross-server inconsistencies before mutation. Current-record merging preserves sibling/order/URL edits. Main-actor write order and installed Codable/Defaults formats remain, including nonthrowing storage failures. New owners introduce no unchecked Sendable, unsafe actor escape, transport or application-global reference.

MediaPlayerManager remains mixed for async preparation/rebuild/queue/provider/supplement lifetime. UserSessionManager remains mixed for deep-link/authentication/sign-in/foreground operation sequencing and shared global freshness. Scoped tests and compiler success do not prove those higher-level operations complete.


Native sweep **56** passes **831** contracts (**802** Swift Testing and **29** XCTest), eight generator checks and three runtime helpers. Unchanged macro inputs retain **18** passing contracts. Boundary **53** and analyzer **35** pass, including a new explicit network-API ban in AccountStore while permitting metadata types and their Defaults bridge. Compile-only tvOS Debug **125**, tvOS Release **50** and iOS Release **69** pass without owned Swift/generated-macro diagnostics.

Accepted preservation audit **434** verifies **1,237** frozen inputs, both original forty-revision SDK graphs and clean tracked checkouts, paid-team/signing/persistence configuration, all five protected local files and equal cancellation-restored progress. Simulator cloud transport remains NO. Metadata426's no-write assertion confused registered defaults with persistent data; it now checks persistent domains. Debug124's missing test-runner link was fixed by explicitly linking AccountStore. The import-only boundary expectation was revised to permit storage types while rejecting request APIs. Audit433's method-range selector was corrected. Failed attempts remain recorded.

**Simulator automation, installation, launches, playback and server-facing diagnostics remain stopped until the human explicitly resumes them.** No live acceptance or server account/catalog/configuration/RAID change occurred. The ledger is **316 retained / 2 mixed / 348 pending / 29 scoped API reviews** among666 app sources. Full items1/2 remain active; physical-device/live CloudKit and independently managed server/release gates remain separate.
