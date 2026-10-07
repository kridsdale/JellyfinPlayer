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
