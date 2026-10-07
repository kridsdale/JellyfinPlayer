# Actor and SDK interoperability review

This review covers the remaining explicit interoperability exceptions in the owned production sources at the permission-extraction checkpoint. The source inventory is a review aid; it is not proof that the complete retained-source/public-API review or current GUI/playback acceptance has finished. Live simulator and server activity remain held by the human.

## Explicit executor bridges

| Source | Execution/lifetime contract reviewed | Verification boundary |
| --- | --- | --- |
| KidsApplication/KidsAppModel.swift, identity subscription | The model and account host are main-actor owners. `receive(on: DispatchQueue.main)` precedes the synchronous `assumeIsolated` update. Immutable account identities are compared before changing the revision, so duplicate identity emissions do not invalidate work. | Source review and Swift 6 compilation. Current GUI identity-switch acceptance is held. |
| KidsArtworkUI/KidsArtworkStore.swift, memory warning | Main-queue delivery precedes the synchronous main-actor trim. The closure captures the store weakly. Invalidation removes the subscription, cancels image flights, clears pixels, and invalidates the byte owner. Memory pressure changes the retention generation rather than triggering a visible grid reload. | Source review and compilation. Current UIKit memory-warning delivery remains unexecuted. |
| SwiftfinScrolling/EPGScrollProxy.swift, horizontal and vertical KVO | Main-thread delivery stays synchronous to preserve the reentrancy guard around mirrored content offsets. Foreign-thread callbacks enqueue a main-actor task. Weak scroll/owner captures, connection generation and active-observation membership reject callbacks after disconnect/replacement. Disconnect invalidates both token maps. | Source review and compilation; native geometry contracts do not establish actual UIKit KVO delivery. |
| Shared/Services/Notifications.swift, accessibility notification | `MainActorKey` moves notification delivery to the main queue before querying UIKit through its actor-isolated decode closure. It supports notifications without userInfo; ordinary payload keys keep their existing decode behavior. | Source review and compilation. This remains a platform notification-key composition adapter. |
| Swiftfin tvOS/App/KidsAccountAdapter.swift, identity projection | The adapter owns the main-actor session manager. Main-queue delivery precedes reading session state and constructing a checked-Sendable identity; raw SDK user/session/Keychain types do not cross the KidsAccountHost identity port. | Source review and compilation; current account-switch GUI acceptance is held. |

These are deliberate synchronous bridges at SDK/Combine boundaries, not a blanket replacement for actor hops. Their scheduler/thread guards must remain adjacent to `assumeIsolated`. Moving an upstream publisher or removing its scheduling step requires reviewing the bridge again.

## CoreStore startup compatibility

`SwiftfinStorage/CoreStoreBootstrap.swift` contains the sole owned `@preconcurrency` import. It wraps one write to the pinned CoreStore 9.2.0 global logger, which has no Swift 6 actor annotation. Normal database/schema/operation sources import the SDK with checked concurrency.

`StorageLoggingStartupGate` admits installation only in its fresh phase. The first installation closes that phase; database construction freezes the gate before creating its DataStack. Repeated bootstrap and bootstrap after database construction are rejected. Adjacent native contracts exercise both orderings through an injected writer; they do not mutate the SDK global in their gate tests. The app's configure composition installs the logger before starting storage/cache composition.

The review establishes ownership of this startup write. It does not prove arbitrary third-party initialization outside the owned database path safe. Keep the SDK pinned and review the shim when the SDK gains native concurrency annotations.

## Permission callback ownership

SwiftfinPermissions exposes only checked-Sendable statuses/errors and two main-actor query/request namespaces. Fresh private LAContext/CLLocationManager drivers own each request. Nonisolated callbacks snapshot owned values and communicate through checked lock-backed callback/continuation receipts; terminal completion and cancellation clear the continuation exactly once. Actor cleanup invalidates authentication and clears location callback/delegate leases. No application source imports LocalAuthentication or CoreLocation after extraction; the boundary checker enforces that rule.

Cancellation completes a waiting location request even if the SDK never replies. The public location SDK cannot withdraw an authorization dialog already requested: cleanup means delegate/callback retirement, not dialog dismissal. Native tests use fake drivers and synthetic results, with no actual permission query, location service or biometric session.

## Public native handles and composition

The reviewed native owners retain SDK clients, players, contexts, managers, storage stacks and observer handles privately. JellyfinTransport's public version is an immutable SDK version value; it is not its mutable client. Request/response SDK DTOs remain values at inherited feature boundaries. The mpv owner's explicit semantic-caption interoperability value remains immutable; renderer teardown still needs runtime acceptance because the pinned SDK has no awaited shutdown API.

The platform App initializers call Shared/App/SwiftfinApp+configure.swift. UserSessionRootView composes the KidsAppModel with SwiftfinKidsAccountHost and the playback factory. Settings, selected credentials and approved catalog binding are supplied by these application adapters; reusable owners do not resolve the application Factory container. iOS platform navigation, household signing and iCloud registration remain separate from the tvOS simulator acceptance gate.

## Remaining review work

- Classify every retained application source by UI, composition or behavior; do not infer completion from file counts or a clean import search.
- Review the full public API and consumer graph, not only the native-handle names above.
- Remaining concrete candidates include the reusable CurrentDate observation and EPG program-span grouping; inspect their dependencies and behavior before choosing an existing library owner.
- Final navigation, decoder/render/output teardown and restricted-account playback/recovery remain held. Compilation and fake-driver tests cannot satisfy those gates.
