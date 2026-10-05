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
