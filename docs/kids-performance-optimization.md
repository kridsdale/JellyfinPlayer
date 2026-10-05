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
