# First measured latency improvements

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
