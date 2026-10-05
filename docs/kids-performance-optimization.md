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
