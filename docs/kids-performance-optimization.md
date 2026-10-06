# Measured latency improvements

Candidate source `655e8655`, simulator executable SHA256 `14ca6395bcbc14c858d10b09b916535b78bcfacb0a262b4db58b2256ea15eeaa`, probe revision 2. Verified installed hash during execution and revision in all six trace runs. Three profiling tests passed: three TV starts, four movie starts, and four fresh-process/artwork sweeps. All seven playback timing samples include observed video output, advancing clock, and player-surface evidence. This is simulator validation of one H264 show and one H264 movie, with warm server/storage caches.

| Metric | Original baseline median | Verified candidate median | Candidate n |
|---|---:|---:|---:|
| Launch to catalog ready | 8.277 s | 2.949 s | 6 |
| TV Play to first observed video output | 10.898 s | 0.824 s | 3 |
| TV Play to player surface | 11.332 s | 1.365 s | 3 |
| Movie Play to first observed video output | 1.378 s | 1.057 s | 4 |
| Grid art request to presentation opportunity | 172.124 ms | 167.064 ms | 121 |

TV episode selection now takes about 9–14 ms from the verified in-memory episode cache. Each TV start has six instrumented HTTP requests and one ancestor lookup, down from 117 and 86. Final selected-item authorization remains fresh. The cold show entry remains material: 4.583 s to display actions in one observation, compared with the original 9.620 s median. Opening a show and pressing Play are separate waits; the warm Play result does not remove the cold entry cost.

Implementation uses a persistent API session scoped to server URL, server identity, user identity and token; joined overlapping catalog refreshes; the dedicated `/Shows/{id}/Episodes` endpoint; and a five-minute, 12-show actor cache of verified episode metadata. It preserves ancestry, expected-kind and selected-item checks. Seven actor tests cover isolation, forged/ambiguous records, capacity/expiry, shared fetches, cancellation and invalidation races. The complete native suite has 62 passing tests. No full media prefetch or RAID writes were introduced.

## Evidence and limits

The [sanitized aggregate](performance/2026-10-05-opt02.json) retains timing distributions, individual successful starts, cancellations, incomplete spans and non-playback failures. Six initial catalog spans and eight artwork fallback spans failed; those are retained and require separate lifecycle/fallback analysis. No candidate playback timing sample failed. First output uses cumulative libVLC counters; surface timing is a presentation opportunity rather than a GPU fence. These figures do not isolate disk seeks, prove hardware decoding, cover all formats, or establish population percentiles.

A finite server observer ran from 04:17:11.333Z to 04:23:11.363Z on October 5 UTC. The client invocation began at 04:20:24.394Z and continued beyond the observer window. It sampled no active NowPlayingItem, so it cannot provide per-stream codec or decode evidence. Whole-window CPU and RSS differences are not attributed to optimizations because workload and idle fraction differ. Client decoded-output/clock evidence validates the seven starts. Audit playback reporting as a separate issue rather than treating absent server samples as no playback.

The preceding opt01 run passed UI playback but XCTest launched the retained JellyfinPlayer 1.4.1 executable. It is explicitly excluded from optimization comparisons. The harness now selects the configured Xcode target, asserts the KidsJellyFin application name, and stamps a numeric probe revision. The old accepted app artifact is retained for rollback.

Both runs' complete simulator playback states were restored through the SDK and compared equal to the original scoped snapshot. The legacy JSON file remains unchanged. Profiling is opt-in; normal launches disable it. Further work remains on cold title loading, artwork pooling/caching and bounded prefetch, duplicate SDK metadata/bitrate work, prompt decoder-driven presentation, missing metadata/render cases, and broader Swift 6 migration.

## Artwork reuse and focused prefetch

Candidate source `e538bccb`, executable SHA256 `687dde532e72fece95a376af6a82541d8d4eb35de70f8b4619a544c1af7ca130`, probe revision 3. The installed executable matched the compiled candidate during testing; all six launches recorded revision 3. Three profiling tests passed again, with seven starts showing video output, an advancing clock and a presented surface. [Sanitized opt03 aggregate](performance/2026-10-05-opt03.json).

| Metric | Prior verified candidate (opt02) | Artwork/prefetch candidate (opt03) | Opt03 n |
|---|---:|---:|---:|
| Launch to catalog | 2.949 s | 2.962 s | 6 |
| Grid art to presentation, all loads | 167.064 ms | 109.641 ms | 121 |
| Grid art, measured memory hits | — | 24.301 ms | 39 |
| Grid art, network loads | — | 144.874 ms | 82 |
| TV Play to output | 0.824 s | 0.997 s | 3 |
| TV Play to surface | 1.365 s | 1.499 s | 3 |
| Movie Play to output | 1.057 s | 0.820 s | 4 |

Artwork P95 improved from 195.157 to 173.819 ms in this sweep. The mix of first loads and revisits is the same 121 grid presentations; cache hits and network loads are now separated in the analyzer. Missing art without an image tag uses a normal placeholder, not a failed HTTP request. There were no artwork failures in opt03. The TV sample was slightly slower than opt02; the small playback samples do not establish an additional speedup or sustained percentiles.

Show actions appeared in 83 ms in one entry. Prefetch had started 4.713 s before title selection and took 4.803 s overall. This shifts verified episode lookup earlier; it does not eliminate that work or promise an 83 ms immediate cold selection. Canceled focus warmups still share their bounded metadata fetch with a subsequent real selection. Background warming never queues a second show's scan behind another metadata flight; deliberate user selections remain available.

The image pool uses one ephemeral connection session, single-flight loads, four active requests, at most 64 pending downloads, a 24 MiB/96-entry compressed-data LRU, and a 48 MiB/64-entry prepared-pixel LRU, with five-minute expiry. UIKit prepares images asynchronously before publication. Focus must rest for 350 ms; its finite plan includes only the focused show's episode metadata and up to three approved adjacent images. No streams, playback-info requests, bitrate probes or complete media assets are prefetched. Cache identity follows the full API identity and exact approved binding; account/token/server changes, authorization failure, sign-out and an explicit Parents refresh invalidate it. Every Play still performs fresh selected-item authorization.

The native suite has 73 passing tests, including artwork isolation, image owner/tag/size keys, capacity/expiry, cancellation/invalidation races, four-request concurrency, and bounded category/focus plans. Six analyzer and six App Store client tests passed. Release build-for-testing and all three live profiling methods passed. Opt03 produced 16,628 events across six traces with zero malformed lines. Six short pre-session catalog failures and canceled warmups remain in the aggregate. No server observer ran for this trial. Full simulator state matched its pre-test backup after SDK restoration; the legacy state hash remained unchanged, and the app was relaunched without profiling.

Remaining optimization and robustness work includes duplicate SDK metadata and bitrate work, decoder-driven presentation, playback-report timing, the excluded metadata/render cases, memory-pressure handling, broader Swift 6 migration and physical-device/format coverage. New cache and prefetch contracts compile in Swift 6; the inherited app target remains in Swift 5 language mode. Server tuning remains conditional on measured evidence and RAID write protection.

## Decoder-driven startup and one full metadata fetch

Candidate source `d2405816`, simulator executable SHA256 `10e230b2e3f1b0c175564dc0d3ec92326e5d641f765178466fea1f8e51fc803f`, probe revision 4. Compiled and during-test installed hashes matched; all six launches report revision 4. [Sanitized opt04 aggregate](performance/2026-10-05-opt04.json).

| Metric | Artwork candidate (opt03) | Startup candidate (opt04) | Opt04 n |
|---|---:|---:|---:|
| TV Play to output | 0.997 s | 0.796 s | 3 |
| TV Play to surface | 1.499 s | 1.032 s | 3 |
| TV output to surface, per-start median | 0.482 s | 0.260 s | 3 |
| Movie Play to output | 0.820 s | 0.931 s | 4 |
| Movie Play to surface | 1.299 s | 1.290 s | 4 |
| Grid art to presentation | 109.641 ms | 97.789 ms | 121 |
| Launch to catalog | 2.962 s | 2.998 s | 6 |

The TV surface wait improved in this small trial; movie surface was essentially unchanged, and movie first output was slower. This does not establish general speedups across codecs or devices. The readiness consumer subscribes to a bounded independent VLC event stream before opening media. It requires displayed-picture evidence and an advancing clock beyond the requested resume position, with the seek applied and no preparation/buffering. Playing state alone no longer begins the viewing session. The one-second timer remains for checkpoints, countdown, recovery and a fallback state check. Stop/deinit cancel the subscription.

The per-start full item fetched by the controller is passed to the provider rather than fetched again. Identity is checked against an immutable server/user/URL/token snapshot before provider preparation; final selected-item policy, type and ancestry authorization remains fresh. The trace now contains one full SDK metadata GET rather than two, with seven metadata operations for seven starts. Request accounting has two scopes: the existing `http` operation counter remains six (policy/server/libraries/items/ancestry plus bitrate), while eight request spans have network metrics, including SDK metadata and PlaybackInfo. Opt03 had nine. Neither counts uninstrumented native stream/preview requests. The failed expectation that `http` alone would drop to five was corrected; restored state was verified separately afterward.

All three real-server profiling methods passed again: seven starts show output, advancing clock and player surface. The native suite has 77 passing tests, including failed/no-output readiness, pending or stale resume clocks, buffering/preparation and invalid numeric inputs. There were 16,600 events, zero malformed lines, six brief pre-session catalog failures, and no artwork or playback failure samples. Complete simulator state matched its backup after SDK restoration; legacy JSON was unchanged and the app relaunched without profiling. No server capture or configuration changes occurred in opt04.

The separate read-only server audit found one excluded series with an explicit season-1/episode-0 entry and 17 other numbered entries; current strict regular-episode validation rejects the zero entry. All episode ancestry links and saved allowlist matches were verified. Its numbering matches the saved migration baseline; semantic numbering correctness is not established. The excluded movie uses AVI/MPEG-4 Advanced Simple Profile, 8-bit yuv420p, with AC-3 audio. That differs from successful H264 fixtures but does not prove source corruption or a decoder defect. No media bytes, scans, repairs, renumbering, conversion or RAID writes were performed by that audit. These cases require separate client/metadata acceptance decisions and evidence.


## Memory pressure and ordered playback reporting

Client source `07f4fac4` adds a strict Swift 6 reporting worker, Combine lifecycle/timer bindings, memory-warning eviction and failed/recovering startup gating. Source `7af81f53` additionally rejects native VLC callbacks for stopped, failed or replaced playback items. The final opt07 executable SHA256 is `2cba99f1eceab8fe350753dd8378be227fa2b774c2416d2063b7c545c36abaca`, probe revision 7; installed hash matched during execution and all three launches recorded that revision. [Opt07 aggregate](performance/2026-10-05-opt07.json).

The tvOS observer starts reporting after decoded output and an advancing clock prove playback. It captures the authenticated client and immutable report snapshots rather than resolving the current account for each queued request. One async worker sends requests in order, retaining only the newest pending progress snapshot. A final stop closes ingress and cannot be displaced by later updates. Failed starts retry on a later update instead of sending progress before acknowledgement or spinning; request failures remain visible. Workers are chained across videos so an old delayed stop drains before the next start. The player and UI never await this reporting chain. No new report is issued for a failed startup that never met readiness.

Cross-video ordering matters because Jellyfin's [session implementation](https://github.com/jellyfin/jellyfin/blob/master/Emby.Server.Implementations/Session/SessionManager.cs) removes device NowPlaying state when processing a stop. Per-video serialization alone would still allow a delayed previous stop to clear a newer session. Weak item/manager references remove the old observer-to-item retain cycle. The iOS legacy progress observer is unchanged; the app target still uses Swift 5 while the new core compiles under Swift 6.

A Combine memory-warning subscription releases both compressed art and prepared-image cache entries without changing the UI revision or invalidating the approved account/library binding. Visible loads finish normally. Pre-warning flights return to their consumers but cannot refill the trimmed cache; later eligible requests may cache again. This prevents memory pressure from triggering an immediate grid-wide reload. It preserves the existing 24 MiB compressed and 48 MiB prepared cache limits. Actor tests verify eviction, continued authorization and in-flight completion without refill; this trial does not claim a measured memory-warning speedup.

| Metric | Prior opt04 | Final opt07 | Final n |
|---|---:|---:|---:|
| Launch to catalog | 2.998 s | 3.128 s | 3 |
| TV Play to observed output | 0.796 s | 0.806 s | 4 |
| TV Play to surface | 1.032 s | 1.107 s | 4 |
| Movie Play to observed output | 0.931 s | 0.769 s | 4 |
| Movie Play to surface | 1.290 s | 1.290 s | 4 |
| Playback start report completion | unmeasured | 54.056 ms | 8 |
| Progress report completion | unmeasured | 45.030 ms | 20 |
| Stop report completion | unmeasured | 45.794 ms | 8 |

This pass improves lifecycle correctness; these small, differently composed trials do not establish an additional general startup speedup. Opt04 had three TV starts; opt07 includes the extra longer ordered lifecycle. Launch was slower, TV presentation was slower, movie output was faster and movie presentation was essentially unchanged. Reporting timings measure HTTP completion separately from preparation/stream requests. Fresh selected-item policy/type/ancestry checks still run before playback. The narrow per-start `http` counter remains six.

Opt06 passed all four UI methods, including the full artwork/fresh-launch sweep, with eight validated starts. Its grid-art median was 156.693 ms across 128 loads, slower than opt04's 97.789 ms across 121; do not claim this resilience change sped up art. [Opt06 aggregate](performance/2026-10-05-opt06.json). Opt07 rechecked the modified playback lifecycle with three methods and eight validated starts rather than repeating the unchanged full art sweep. Native tests: 64 core plus 23 persistence, all passing. Analyzer tests: eight passing. Final trace: 6,939 events, zero malformed lines, three retained pre-session catalog failures, no artwork/playback/report failures. Two rejected playback-status requests during dismissal and synchronous audio-session activation warnings remain; the native-callback guard does not establish that every lifecycle warning is fixed.

### Independent server validation, opt05 only

The earlier opt05 executable (probe 5, SHA256 `1a8af1257e584df782a923d2db43413a41942e4938eea3eccb7768420f96ce65`) passed a deliberately longer play/pause/stop test followed by the three original profiling methods. Its client start-report request began 0.867 ms after the decoded-playback marker and succeeded in 64.510 ms. Its first stop succeeded at 13:59:05.139 UTC on October 5. [Opt05 aggregate and server lifecycle facts](performance/2026-10-05-opt05.json).

The server's finite read-only observer captured 60 samples at three-second cadence with zero API/scope/collector errors. During the first lifecycle it observed seven playing samples with increasing position, then three paused samples with fixed position, then five consecutive clear samples from 13:59:07.578 to 13:59:19.618 while the restricted client session remained present. Session disappearance and failed queries were excluded from clearance evidence. Later short TV tests appeared before capture end; the final sample was paused, so completion of capture is not proof that all subsequent tests stopped. This evidence supports opt05 reporting and is not attributed to opt06/07's later cross-video chain. The source descriptors were scoped metadata, not hardware-decoding evidence. Server and observer RAID write denial were verified at start and end; no server configuration changed.

Each trial's entire simulator-local playback state was restored through the SDK and compared equal to its retained backup. The legacy JSON hash stayed unchanged. Profiling remains opt-in and the final app was relaunched normally after restoration. No media catalog expansion, full-media prefetch, RAID mutation, cache purge, file repair or conversion occurred.

Remaining work includes cold title/catalog latency, the excluded numbering and MPEG4/AVI cases, the source of rejected dismissal status requests, asynchronous audio-session activation, broader codec/hardware playback validation and staged migration of inherited code to Swift 6. CI workflow publication still requires the pending explicit GitHub scope authorization; it does not block local client optimization.


## Verified progressive browse and asynchronous audio lifecycle (opt08-opt10)

The latest candidate is stamped probe revision 10, executable SHA256 `dcdf748bc1f6ec3658da9657f90bf9145c9234cf45e643485adc33368a6908e5`, based on `82ef33b4` with the source-file hashes retained in the [opt10 aggregate](performance/2026-10-05-opt10.json). The installed executable matched and the complete simulator progress state was restored through SwiftData SDK operations and compared equal to the retained snapshot.

Catalog loading now validates the account before publishing any data, fetches both scoped categories concurrently, and exposes stable cumulative prefixes only after each entry's kind and ancestry are verified. The selected category publishes first; denied entries are excluded even from partial snapshots. Later failure clears the catalog. Parent help remains reachable while a category loads. Automatic episode prefetch waits for full catalog completion, avoiding competition with outstanding catalog checks; explicit title entry remains available. New HTTP tests cover selected-category ordering, wrong-library prefix exclusion, policy denial, cancellation and late failure.

| Opt10 measurement | Median | n |
|---|---:|---:|
| Launch to first approved Shows prefix | 1.451 s | 7 |
| Launch to first approved Movies prefix | 1.529 s | 7 |
| Launch to first browse | 1.495 s | 7 |
| Launch to complete Shows catalog | 2.236 s | 7 |
| Launch to both complete catalogs | 3.676 s | 7 |
| Grid art to presentation opportunity | 204.172 ms | 128 |
| Ordered TV Play to observed output | 1.868 s | 3 |
| Shuffle TV Play to observed output | 1.929 s | 1 |
| Movie Play to observed output | 2.338 s | 4 |
| Native terminal-player shutdown/drain | 61.274 ms | 8 |
| Audio activation | 0.305 ms | 8 |
| Audio deactivation | 0.037 ms | 8 |

First visible browse and full completion are deliberately separate metrics. These later warm-server H264 simulator samples do not show an additional playback or artwork improvement over opt04/opt07. No physical-device, disk-seek or broad-format result is inferred. No independent server observer ran for these trials. The server logging cleanup and boot diagnostic staging overlapped the early trials, so timing changes are not attributed exclusively to client changes.

The transport setter now updates immediately on the main actor rather than scheduling a state-machine request that could execute after Stop. Audio activation/deactivation uses a process-wide ordered lease coordinator; category setup and older-OS compatibility calls run off the main actor. VLC waits for activation before opening output. A terminal player's full native shutdown drains output before releasing its audio lease. Old stopped/failed/replaced players cannot resume from late transport, image or interruption callbacks. All eight opt10 activation, drain and deactivation operations succeeded; the maximum drain was 65.929 ms. The previous main-thread audio activation and rejected-dismissal warnings were absent in the opt08-opt10 runtime logs. This does not establish hardware interruption behavior.

Failed experiments are preserved. [Opt08](performance/2026-10-05-opt08.json) tested a larger per-host connection pool without measured benefit; that change was removed. [Opt09](performance/2026-10-05-opt09.json) passed its UI assertions but recorded five ten-second stop-only drain failures, so it is excluded as a final acceptance candidate. Opt10 replaces that wait with terminal native-handle shutdown.

Opt10 passed four Release profiling methods, eight genuine starts and seven launches. The trace contains 17,275 events, zero malformed lines and seven retained brief pre-session catalog failures; no artwork, playback, report, audio or native-drain failure was recorded. Native core/HTTP and persistence: 69 plus 23 tests pass. Analyzer: ten tests pass. New navigation, platform compatibility and broader format checks remain separately reported. No RAID file changes, media conversion, full-media prefetch or catalog expansion occurred.


## Swift 6 verification and final measurement correction (probe 11–12)

The app targets now compile in Swift 6 with explicit UI/session ownership. Main-actor handler crashes observed during real pause/play were repaired at the app's asynchronous method boundaries; no dependency checkout was patched. Failed trials and the exact checkpoint Retry repair are retained in [the modernization report](engineering/swift6-modernization.md). A separately approved AVI/MPEG4+AC3 movie now has actual frame, pause/resume and advancing-clock evidence; the representative timing samples below remain H264.

The final Release simulator executable is SHA256 `dc0f409591c55d0c17cbe690f6d0d08fee60cb64be0217e72ac9abb98710fb02`, probe 12. Its installed hash matched; ad-hoc signature verification passed and Debug preview/fault arguments are absent. Both tvOS Release build-for-testing and the latest iOS Release compile passed. Native core/HTTP and persistence: 69 plus 23 tests pass. Three production utility suites, ten analyzer tests and six App Store metadata tests also pass. Hardware provisioning and live iCloud delivery are explicitly deferred by the user.

| Median measurement | Swift 6 baseline 11 | Final probe 12 | n each |
|---|---:|---:|---:|
| Launch to first approved Shows prefix | 1.323 s | 1.068 s | 2 |
| Launch to first browse | 1.366 s | 1.107 s | 2 |
| Launch to complete catalog | 3.374 s | 3.185 s | 2 |
| Grid artwork presentation | 110.620 ms | 123.572 ms | 29 |
| Ordered Play to observed output | 0.966 s | 1.103 s | 2 |
| Shuffle Play to observed output | 0.876 s | 0.816 s | 1 |
| Movie Play to observed output | 1.115 s | 1.444 s | 4 |
| Bandwidth probe operation | 43.956 ms | 44.747 ms | 7 |
| Native player shutdown/drain | 60.592 ms | 64.858 ms | 7 |

These paired small trials do not establish a speedup. Final movie output was slower; artwork and ordered output were also slower. First output uses native displayed-picture counters sampled every 50 ms; a surface marker is a run-loop presentation opportunity, not a GPU fence. None of these values isolates the RAID's mechanical seek time, and no OS/server/drive cache was purged.

The actual response `Data.count` and URLSession network byte count were both 8,388,608 bytes for all seven final bandwidth samples, despite a requested 5,000,000 bytes. The estimator now uses the actual received payload and `ContinuousClock` duration, rejects empty/invalid measurements and bounds the conversion. This is a measurement-correctness fix, not an established latency optimization. It adds no request. All seven starts retained six instrumented catalog/bitrate HTTP requests plus separately instrumented SDK metadata/PlaybackInfo requests and fresh selected-item authorization.

The earlier opt10 bandwidth cost was about half a second; baseline 11 and final 12 instead measured about 44–45 ms. Environment/workload variation prevents attributing that difference to Swift 6. A native-tested, identity-bound cache prototype remains an unshipped experiment: eliminating a current 45 ms probe would save only a small part of startup while retaining an older estimate. It was not integrated. The old larger-connection-pool experiment also lacked benefit and remains removed.

One baseline show entry waited 2.652 s for an already running verified episode fetch; that fetch took 5.674 s overall. Final episode prefetch took 2.520 s and completed before title entry, which then took 21.943 ms. This is a warmup/timing difference, not removal of the cold work. The remaining cold wait is full scoped episode validation and per-item ancestry, including network queue/first-byte latency. The current decision is to retain those boundaries and the bounded metadata warmup rather than remove checks or add another scheduling/cache layer without a repeatable benefit. Physical-device measurements should guide the next latency change.

`Kids-Swift6-Final-12.xcresult` passed three selected methods: two profiling methods (seven validated H264 starts) plus the separate exact approved AVI test, 124.178 s total. The final trace has 3,944 events, zero malformed lines, two retained pre-session catalog failures, and no artwork/playback/audio/drain failure. Complete original simulator progress was restored via SwiftData and compared equal, and the app was launched normally without profiling. [Baseline 11 aggregate](performance/2026-10-05-swift6-baseline-11.json) and [final 12 aggregate](performance/2026-10-05-swift6-final-12.json) retain source/build identity and sanitized distributions; raw traces remain private.

The independent server observer for the earlier EOF/cap run corroborated same-session NowPlaying clearance, approved DirectPlay and maximum sampled concurrency one, with RAID write denial at start/end. It did not overlap probe 11 or 12 and is not used to infer their stream codecs, hardware decoding or server latency. No server tuning, media mutation, catalog expansion or full-video prefetch was performed for these trials.
