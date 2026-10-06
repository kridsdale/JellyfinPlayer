# Client package refactor and Swift 6 completion

Active goal: complete the minimal-responsibility package refactor and remaining Swift 6 compatibility warnings. This document records scope and evidence, not a narrower replacement objective.

## Initial source map

Before extraction the app compiled 614 Shared Swift files, 32 tvOS Swift files and 108 iOS Swift files. The single KidsCore library mixed domain contracts, network authorization/catalog reads, episode and artwork caches, readiness/reporting and diagnostics. KidsPersistence was a second product in the same package. SwiftfinMacros and PreferencesView already existed separately. App globals (Factory sessions, defaults, SDK player types) coupled the kids presentation/model/player together.

## Independent packages extracted first

| Package | Owns | Direct dependencies |
| --- | --- | --- |
| SwiftfinLocalization | Typed localized display strings, all 54 language resources, deterministic read-only build-tool generation | Foundation |
| SwiftfinUIState | Main-actor observable value boxes and binding adapters | SwiftUI, Combine |
| KidsDiagnosticsUI | Presentation-frame trace probe | KidsDiagnostics, SwiftUI, UIKit |
| KidsAccounts | Secure account host port, redacted full network identity, staged credential storage and exact binding activation | KidsDomain, Foundation, Combine |
| KidsArtworkUI | Prepared UIKit pixels, single-flight decode and bounded ephemeral pixel retention | KidsDomain, KidsCatalog, KidsDiagnostics, KidsArtwork, UIKit |
| KidsDomain | Immutable identity/content contracts, eligibility, user-visible failure contracts, ordered/Shuffle/session rules and parent-gate timing | Foundation |
| KidsDiagnostics | Opt-in bounded numeric traces and network timing delegate | KidsDomain, Foundation, OSLog |
| KidsCatalog | Exact-scope API/policy/ancestry authorization, verified episode metadata cache | KidsDomain, KidsDiagnostics |
| KidsArtwork | Account-scoped bounded image data cache and finite approved focus warmup plans | KidsDomain, KidsCatalog, KidsDiagnostics |
| KidsPlaybackSession | Playback transport/recovery/countdown state machine, native-driver and application-callback ports | KidsDomain, KidsPlayback, KidsDiagnostics, Foundation, Combine |
| KidsPlayback | Decoded-output readiness, ordered playback reporting, bounded monotonic bitrate measurement | KidsDiagnostics |
| KidsPersistence | SwiftData/private CloudKit records, merge/reset semantics and immutable legacy JSON migration | KidsDomain, KidsDiagnostics |

Each has its own Package.swift and adjacent tests. No production aggregate KidsCore facade exists. The old KidsCore directory remains a development-only KidsStateTool/cross-package integration executable, preserving the authorized simulator-state helper command path. App files import their actual dependencies directly.

KidsPersistence module identity, model name, entity properties, cloud container ID, namespace encoding and JSON schema are preserved. Moving its package path must not imply a data migration. An SDK integration test checks the persistent model identity, durable reopen and readiness beyond the persisted resume clock.

## Remaining work before completion

- Finish extracting kids presentation/application state and the inherited native-player implementation. Account/session/Keychain access is injected through KidsAccounts; the kids session state machine now lives in KidsPlaybackSession behind native-driver and application-delegate ports. The retained SDK/native adapters stay at the app composition boundary until their own implementation libraries are separated.
- Partition remaining inherited client responsibilities into coherent packages based on actual dependency edges. Do not leave the app target as a large library or add a catch-all shared facade.
- Resolve app/macro/SDK/Binding/defaults/view concurrency diagnostics by correct ownership and value transfer, not blanket suppression.
- Run every independent package test plus both platform integration builds, current navigation and real restricted-account playback/recovery checks after meaningful integration changes. Preserve full simulator state and keep RAID media immutable.
- Document final dependency graph, public interfaces, owner actors, composition root and extension path; enforce boundaries and audit every original criterion before completion.

Physical Apple TV and live CloudKit transport checks remain explicitly deferred by the human. Server/catalog/account/RAID changes and GitHub workflow publication are outside this goal.

## Verified checkpoints (2026-10-06)

- Native library run 03: 93 Swift Testing contracts/integration checks plus six XCTest account-port checks pass; all three runtime utility suites pass. The account tests cover credential replacement, redaction, deferred activation, exact staged library binding, failed secure storage, and activation errors.
- Full tvOS Debug build 06 passed with no Swift compiler or generated macro warnings. The library/provider/editor protocols now permit transferable type metadata while retaining main-actor operations; stable library IDs no longer read mutable UI state from nonisolated identity consumers. Base fetch values are Codable and Sendable.
- Real-server run 06 passed episode pause/seek/resume/relaunch, movie pause/seek/resume, Shuffle, and the already-approved AVI movie. Full simulator progress was backed up, restored through the SwiftData SDK, exported again, and compared equal. These tests predate the subsequent account/UI-artwork extraction.
- iOS Release compile 03 and tvOS Debug 10 passed with zero Swift compiler/macro warnings after the account, prepared-artwork, shared UI-state and diagnostics-UI extraction. Four SwiftfinUIState contracts pass.
- Account/artwork acceptance run 09 passed all 21 tests: three UIKit pixel/identity checks, 16 navigation checks and two real recovery checks. Complete simulator state was restored through the SDK and exported equal to the original backup. These checks predate the subsequent UI-state/probe/localization extraction.
- Localization package run 01 passed four native resource/format/API checks; eight real generator checks pass, including positional format errors and preserving prior output on failure. All 54 moved language files match HEAD byte-for-byte; all 964 generated API names retain their original order. tvOS Debug 11 integrates the plugin and resource bundle with zero Swift compiler/macro warnings.
- The boundary verifier passes twelve individually owned libraries with exact declared dependency edges and no cycles/hidden exports; eight verifier tests pass. This checks extracted libraries only, not completion of the inherited client partition.
- Failed builds 01 through 05 and account integration 07 are retained. In particular, making entire UI values nonisolated was rejected; final UI owners remain on the main actor. NSObject layout equality instead reads lock-protected immutable UIColor snapshots, and geometry callbacks capture a Sendable coordinate-space value.

Artifacts are in build/validation/Kids-Packages-*.xcresult and private temporary build logs. No graph-wide completion claim is made: most inherited app responsibilities and native playback/UI still require extraction, and final Release/runtime verification remains outstanding.

## Playback-session boundary (2026-10-06)

KidsPlaybackSession owns main-actor child transport state, decoded-output readiness, durable failed-open Retry, periodic checkpoints, 15-second buffering recovery, paused seeking, the next-episode countdown and idempotent stop. Its nine deterministic native behavioral tests pass. The driver exposes only Sendable snapshots and classified failure events; it accepts start/report/pause/seek/stop commands. The application delegate owns exact active-session checks, authorization failure handling, persisted progress, next-title selection and session limits.

The app's SwiftfinKidsPlaybackFactory preserves exact server/user/URL/token checks in the native item-provider closure. Raw Jellyfin DTOs, player managers, VLC, native surfaces and audio/subtitle track values remain inside the host adapter. Every native track mutation calls the existing parent gate before changing the selection. No SDK types or Factory global imports cross the session-library port.

Native run 05 passed 116 library/integration checks, eight real generator checks and all three runtime utility suites, with zero compiler warnings. Run 04 is retained: its server-display-name identity test failed because automatic equality/hash included display metadata. The explicit four-field network identity now excludes that display field while still detecting server URL/ID, account and token replacement; tests and a subsequent formatted simulator build confirm the contract.

Simulator acceptance 13 passed 24 of 25 checks, including all 16 navigation, three UIKit artwork and five real playback/recovery checks. The first approved AVI startup reached Recovery. A focused opt-in diagnostic rerun 14 passed, preserving the original 30-second readiness criterion. Numeric probes recorded provider-ready at 473 ms, decoded output at 1,129 ms and the controls surface at 1,376 ms on that successful sample. These are one simulator sample, not a disk-seek or regression distribution. The initial failure remains recorded and its cause is not yet established. Both runs restored the complete simulator state through the SDK and exported it equal to their respective original backups.

The focused explicit-stop lifecycle, genuine EOF/next-item and two-episode-cap tests passed in run 15; the full SDK state restore/export comparison was equal. The independent server capture observed eight consecutive same-session cleared samples spanning 14 seconds, with no observer/authentication/error-level log failures and RAID write denial passing throughout. The earlier AVI log window did not establish its failure cause. Builds 11, 13 and 14 and iOS Release 04 have zero Swift compiler/generated-macro warnings. Build 12 is retained: it exposed the last native track-picker dependency, now at the host boundary. Full-codebase extraction and final Release/runtime audits remain required before completing the goal.

Two additional fresh-process approved-AVI trials in run 16 passed (30.790 s and 33.800 s total test durations), and complete SDK progress restoration compared equal. Together with run 14, three focused AVI starts succeeded after the initial run 13 failure. No assertion, decoded-output criterion, retry behavior or timeout was weakened. The first failure remains unexplained; server application logs contain only informational permission settings in that window.

Full tvOS Release build 02 passed with zero Swift compiler/generated-macro warnings. Release build 01 exposed an existing PreferencesView warning: the tvOS orientation compatibility type is local, so its debug-description conformance cannot be marked retroactive. The conformance is now platform-specific; the imported iOS UIKit type retains its retroactive annotation. iOS Release build 05 also passed with zero Swift compiler/generated-macro warnings. The simulator app was launched normally with no test/fault/profiling arguments and visually observed on the approved Shows browser, without autoplay.
