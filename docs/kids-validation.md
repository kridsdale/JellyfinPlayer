# Kids implementation validation record

Status: **RC1 ready for simulator release-candidate evaluation**. Updated 2026-10-03 (America/Los_Angeles). Branch: `feature/kids-release-candidate`.

## Account and media boundary

The user entered the real `kidsplayer` credentials privately in the simulator. The saved binding and actual catalog/playback use server `da8484ff10f7486e8e486b19c91db348`, user `81015b5fdef84cb4af7740c43aae8e73`, Kid TV `5af46e92f8eafe27a878a84b7850e143`, and Kid Movies `f146a2eeab6dfc87c7cfc04fc89ca28e`. No credentials appear in source, commands, or the test environment.

The server chat verified the account is non-admin, limited to those two existing libraries, and cannot delete content. A read-only audit selected one existing item with existing artwork in each of the four other libraries. Restricted GET item, GET ancestors, GET image metadata, and HEAD artwork returned **16/16 HTTP 404**, while matching admin positive controls returned **16/16 HTTP 200**. No forbidden image/video bytes were fetched. PlaybackInfo and forbidden stream routes were deliberately skipped because this audit did not authorize creating their playback state or retrieving their media.

All client artifacts and local state remain on internal storage. The app uses the curated Jellyfin API; it has no drive scanning or media-file mutation paths. Server observations ran under its existing RAID write-denial boundaries. No library/catalog/account/media changes were part of this validation.

## Passed checks

| Check | Evidence | What it establishes |
| --- | --- | --- |
| Core and HTTP contracts | `swift test --package-path KidsCore`, 26 tests; `build/validation/kids-core-rc.log` | Exact permissions and ancestry, old identity isolation, state corruption, ordered/Shuffle independence, bags, session budgets, gate timing and atomic persistence |
| Complete remote navigation suite | All 15 `KidsNavigationTests` pass in `build/validation/Kids-Live-10.xcresult` | Actual production SwiftUI views driven with synthetic catalog data: browse/category/Back/focus, protected PIN/picker/reset actions, paused timeline remote transport, recovery and endings |
| Real episode transport and relaunch | `Kids-Live-05.xcresult`, 94.780 seconds | Frames, pause, +15-second seek, physical Play/Pause resume, clock progression, terminate/relaunch without autoplay, restored ordered checkpoint |
| Real movie transport | `Kids-Live-06.xcresult`, 40.133 seconds | Frames, pause/seek/resume and advancing time; return to one Resume action |
| Natural episode-to-next | `Kids-Live-07.xcresult`, 92.494 seconds | Actual VLC EOF, ten-second countdown with Stop focused, exact next regular episode playing |
| Actual HTTP failure isolation/recovery | `Kids-Live-07.xcresult`, 64.218 seconds | Real server HTTP denial with a deliberately invalid token, mismatch against real account policy, and real loopback connection refusal; no child cards/player; saved valid account recovers afterward |
| Natural two-episode limit after relaunch | `Kids-Live-09.xcresult`, 71.684 seconds | The genuine first completion budget persisted; actual second EOF produced All Done, no further autoplay, Back to Shows |
| Actual VLC connection refusal and exact retry | `Kids-Live-11.xcresult`, 79.072 seconds | A one-shot refused stream waits for deliberate Retry, then renders the exact approved episode at/after its saved 84-second checkpoint; retained frame is at 1:31 |
| Actual Release Shuffle | `Kids-Release-Live-01.xcresult`, 42.140 seconds | Real approved episode frames and clock progression using the signed Release app; before/after local snapshots confirm ordered Next is unchanged |
| Signed simulator Release | Final `Swiftfin tvOS` Release build and `codesign --verify --deep --strict` | Valid signature; executable strings/symbols exclude both preview and integration-fault hooks; an observed launch with both Debug arguments still displayed the real approved catalog |
| arm64 Apple TV Release compile | Final generic tvOS device Release build, signing disabled | Compiles for physical Apple TV hardware; installation/signing and physical playback remain unverified |

These are separate test results, not one combined all-green run. `Kids-Live-06` also contained a recovery assertion with the wrong expected error message; `Kids-Live-10` also contained the earlier failed stream-recovery check. Those failures were diagnosed and their replacements passed in 07 and 11 respectively. The full navigation suite in 10 had zero failures.

The first live checks reproduced a blurred fullscreen focus surface, poster-driven layout overflow, and a remote Resume press lost while the seek timeline owned focus. The surface now uses a transparent custom button style, artwork cannot dictate layout dimensions, and each focused transport control handles Play/Pause. Now Playing time updates retain paused state and publish rate zero when paused. A real-start watchdog bounds failed opens even without an error notification, and an unexpected stopped clock cannot erase the last valid resume position. The stream test's original 25-second assertion was also shorter than the combined preparation/open bounds; its corrected bound does not waive the production watchdog.

## Natural-end test setup

To observe real EOF without watching two entire episodes, `Scripts/Kids/simulator_resume.py` backed up only the simulator's internal state and temporarily set valid ordered resume positions 25 seconds before the verified runtimes. Episode 1 was `1f74938947519192e646194fd9e6b86c`, season 1 episode 1, runtime 1353.194 seconds. Its immediate regular successor was `4ab00c91031efca8643d24373020a0c5`, season 1 episode 2, runtime 1353.898 seconds. Both belong to the approved Kid TV series `92835060f3344b9b3b57a281e15b5626`.

The second setup required the genuine first completion count and exact next item to already be persisted, and retained the limit of two. It did not synthesize EOF, invoke a completion function, or bypass account/item authorization. The original local progress was restored afterward; the required internal backup remains retained and ignored by Git. Real playback reports may update ordinary Jellyfin watch/progress data; no media/catalog files were modified.

## Independent server corroboration

Read-only session samples showed the approved episode and movie using DirectPlay with advancing positions. The ten-minute record `sessions-20261004T025613Z.jsonl` contains 196 samples, 19 with playback, zero observer errors, and at most one active kidsplayer stream. It recorded episode 1 advancing from 1334.818 to 1350.128 seconds, episode 2 playing afterward, and a later near-end episode-2 run followed by cessation. The client screenshots/assertions establish natural completion, countdown and budget persistence; session sampling alone does not.

Earlier three-second samples captured stable pauses after seeks. Not every short pause/resume falls in a server sample, and a later new session must not be mistaken for remote Resume. Session telemetry also cannot prove rendered frames for a deliberately refused client transport; actual Retry success is established by the client frame/clock assertions in 11.

Server evidence is retained under `/Users/kridsdale/Documents/Codex/2026-09-28/boo/outputs/jellyfin-playback-evidence/` on 1531Server. The access audit is `restricted-reads-20261004T025951Z.json`. These remote paths are evidence references, not files in this local checkout.

## Evidence limits and evaluation

Fault checks are opt-in Debug integration hooks: they substitute an invalid request token, an expected-library mismatch, or a refused local URL without changing saved credentials, server account policy, or household network availability. They exercise genuine HTTP/VLC failure paths but do not claim an actual token revocation, server replacement, or LAN outage. Changed user/server identity and stale artwork ownership are also covered by contract tests, synthetic denial-after-browse UI tests, and reviewed cancellation/scope checks. Parent PIN unlock, Set Next, Start over and relock were exercised with synthetic data; the user's private production PIN was not retrieved or entered by automation.

Physical Apple TV signing/install, audio/HDR/format coverage, sleep/wake, the child's usability observation and the one-week household pilot remain evaluation activities after this simulator candidate. The ten representative starts and <=3-second warm-LAN median are evaluation targets, not measured promises. Server unattended startup and Plex retirement remain separate workstreams.


## SwiftData/iCloud continuation — 2026-10-04

Active kids persistence moved to SwiftData with automatic private CloudKit mirroring for provisioned builds; the old JSON is retained unchanged as a rollback snapshot. See [iCloud architecture, setup and test limits](kids-icloud.md).

- 26 core/HTTP tests and 23 actual SwiftData storage/merge tests pass. The schema test verifies defaults and no uniqueness constraints/relationships. Two-store delivery is a controlled emulation of CloudKit transport, not a live Apple service test.
- All 15 remote navigation tests pass in `build/validation/Kids-iCloud-Navigation-01.xcresult`.
- Actual episode pause/seek/resume/terminate/relaunch, movie playback, and Shuffle pass against the existing restricted LAN account in `build/validation/Kids-iCloud-Live-01.xcresult`. Episode test: 105.378 s; movie: 38.561 s; Shuffle: 50.615 s. These exercised the newly migrated real SDK store.
- The simulator's legacy JSON SHA-256 before migration was `6aa13ecd3b849049c7b68e1b9fdc1f5ab5e2359b9933dd776b33b7cfdc0bb357`; it remained byte-for-byte unchanged after those real playback tests. `progress.store` exists and the SDK export shows updated ordered resume rather than the old JSON being used.
- Developer team is not configured and no valid signing identity was found. Live iCloud transport between signed Apple clients, production schema deployment and TestFlight signing remain unverified. Ad-hoc simulator builds deliberately use local SwiftData and display that status in Parents; generic unsigned hardware compilation does not establish sync.

System transport pause now checkpoints immediately as well. `Kids-iCloud-Shuffle-Resume-02.xcresult` passes the stronger real Shuffle check (103.225 s): seek forward, prove resumed clock progression, pause, terminate/relaunch without autoplay, and resume the exact same episode at/after the saved checkpoint. The first continuation attempt failed because the test sent Right before the title's asynchronous episode load had exposed Shuffle; adding the same title-load wait as the initial launch fixed that test synchronization. No application focus workaround or synthetic stream was substituted. No RAID media or catalog mutations were involved.

- Final signed simulator Release and unsigned arm64 physical Apple TV Release builds pass. Simulator `Info.plist` has `KidsCloudSyncEnabled=NO`; physical target has `YES`. Both include the remote-notification background mode, and simulator code-signature verification passes.
- Automatic hardware signing preflight returns: `Signing for "Swiftfin tvOS" requires a development team. Select a development team in the Signing & Capabilities editor.` This is the exact outstanding provisioning gate, not a simulator/core-test failure.
- The updated SDK-based simulator helper was seeded and restored against the real migrated container. A subsequent SDK export equals every field of the retained original backup. The legacy JSON remains unchanged. No near-EOF completion was claimed in this continuation; the helper smoke test verifies tooling/migration compatibility only.


## Paid Developer team configuration — 2026-10-04

The user added their paid Apple Developer account in Xcode. Saved Xcode team metadata identifies **Kevin Ridsdale (`Z3LBQE3J8T`)**, an individual team with `isFreeProvisioningTeam=false`. That verified team is now the tracked shared build-configuration default and the project targets' automatic-signing team. The ignored local override agrees. Project Release now uses the same shared configuration as Debug, so the validation target inherits the team in both configurations.

- Evaluated `Swiftfin tvOS` Debug and Release settings resolve `DEVELOPMENT_TEAM=Z3LBQE3J8T`, `CODE_SIGN_STYLE=Automatic`, `PRODUCT_BUNDLE_IDENTIFIER=com.kridsdale.JellyfinPlayer`, the JellyfinPlayer entitlements, and `KIDS_CLOUD_SYNC_ENABLED=YES` for hardware. The project passes `plutil -lint`.
- The simulator Release rebuild succeeds without signing overrides (`/private/tmp/kids-paid-team-simulator-release.log`). It remains an ad-hoc simulator build with local SwiftData; selecting a paid team does not make that build a provisioned CloudKit client.
- The first hardware attempt stopped at the already known package-macro validation gate. Retrying with the established `-skipMacroValidation` option reached signing and returned `No Accounts: Add a new account in Accounts settings.` and `No profiles for 'com.kridsdale.JellyfinPlayer' were found` (`/private/tmp/kids-paid-team-device-build-2.log`). The saved account-manager provider lists contain zero accounts, despite the cached paid team, and `security find-identity -v -p codesigning` still reports zero valid identities.
- The hardware provisioning failure is now an Xcode account-access gate, rather than a missing project team. No valid Apple-authenticated signature/profile, container provisioning, hardware install, or live iCloud transport is claimed. The previously passing persistence/playback tests do not need repeating for a team-only configuration edit.


## Performance instrumentation and baseline (2026-10-04)

The opt-in Release simulator baseline and limits are documented in [kids-performance.md](kids-performance.md), with [tracked aggregate evidence](performance/2026-10-04-baseline.json). This work adds measurements only. Fifteen starts of verified representative content produced video-output and advancing-clock evidence. Wider discovery also found one rejected show and one corrupt movie; those remain unresolved and were excluded from success timing distributions. There is no physical Apple TV or library-wide compatibility claim.

The final instrumentation passed 54 native tests, eight HTTP contracts with probes enabled, five analyzer regressions, and two targeted real-playback methods in `build/validation/Kids-Performance-04.xcresult`. Both four-launch artwork sweeps passed in trials 02 and 03; the broader playback methods in those trials failed and are retained as failure evidence. The simulator-only rollback tool restored all original client-state fields and exact Shuffle bag through SwiftData; `build/validation/performance-restore-verification.json` records the comparison and unchanged legacy JSON hash. No RAID media files were modified.


## Current signing retry (2026-10-05)

The Mac now has one valid Apple Development signing identity for Kevin Ridsdale and two saved account-manager provider entries. A hardware Debug build with the interactive account still returned `No Accounts`; using the authorized App Store Connect team API key succeeded in account authentication, then failed because the team has no devices available for a tvOS development profile. No matching embedded profile or signed hardware app was produced. Only simulators are paired in `devicectl`. Physical Apple TV pairing/registration is the immediate human step; live CloudKit export/import between two signed clients, production schema deployment and TestFlight remain unverified. The configured paid team, bundle ID and CloudKit entitlement are retained.

Both tvOS simulator builds and the shared-code iOS Release simulator build compile after the asynchronous audio/progressive catalog changes. These compile outcomes do not substitute for hardware signing or live cloud delivery.

The user explicitly deferred physical Apple TV and live iCloud testing after the signing retry. These remain unverified acceptance gates, not current local engineering blockers to other work.


## Progressive browse and audio lifecycle (2026-10-05, opt10)

Four Release profiling methods passed eight real H264 starts and seven launches. Installed probe 10 matched SHA256 `dcdf748bc1f6ec3658da9657f90bf9145c9234cf45e643485adc33368a6908e5`. All eight native terminal shutdown/drain, audio activation and audio deactivation operations succeeded. Complete scoped state was restored through the SDK and compared equal. See the [aggregate](performance/2026-10-05-opt10.json) and [performance report](kids-performance-optimization.md); this is not broad codec or hardware proof.

The first navigation attempt used the retained Release xctestrun file and is excluded from preview validation. The second used the correct Debug file: twelve tests passed and four seeded-player previews failed because the real identity watcher stopped their synthetic player. The watcher now explicitly excludes previews; production still stops playback before identity/catalog replacement. The third run, `build/validation/Kids-Prefix-Navigation-03.xcresult`, passed all **16** remote navigation tests with zero failures (152.533 s), including pending Movies loading, countdown Stop, parent movie Start over, paused seeking and reconnect Back. No real account or media changed to fix those fixture failures.

Native core/HTTP and persistence: **69 + 23 = 92** tests pass. Profiling analyzer: **10** tests pass. The latest shared-code iOS Release simulator build passes. The selected paid team and simulator ad-hoc identity are kept distinct from hardware signing and CloudKit transport.
