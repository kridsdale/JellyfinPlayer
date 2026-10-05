# JellyfinPlayer latency baseline — October 4, 2026

**Recommendation: optimize the client’s catalog preparation. The payoff is substantial.** TV starts spend a median 9.79 seconds selecting and validating episodes before the player opens. First-screen catalog preparation takes 8.28 seconds. Thumbnail loading itself is about 0.17 seconds. These measurements justify fixing unnecessary API work before tuning the RAID or video buffers.

This change adds opt-in instrumentation, profiling tools and evidence. It makes no performance optimization, cache-policy change, authorization relaxation, server tuning, or RAID modification.

## Observed results

Release build, Apple TV 4K simulator on the Mac Studio, actual restricted Jellyfin account over the home LAN. The catalog contained 30 shows and 128 movies from the two approved libraries. Baseline includes 14 fresh app processes, eight successful launch/category/detail/revisit sweeps, and 15 successful playback starts: six ordered starts and three Shuffle starts of one representative 84-episode show, plus six resumed starts of one verified movie. The final sampled sources were H.264, 510×384 and 1920×802. This is repeated representative-content profiling, not a survey of all codecs or all titles.

| Measured interval | Samples | Median | Observed P95 |
|---|---:|---:|---:|
| App initialization → approved catalog ready | 14 | 8.28 s | 9.50 s |
| Show selection → Next/Shuffle actions ready | 3 | 9.62 s | 9.72 s |
| Thumbnail request/task start → next frame opportunity with image | 279 | 172 ms | 230 ms |
| Thumbnail request/task start → response received | 279 | 147 ms | 203 ms |
| Thumbnail response → presentation opportunity | 279 | 25 ms | 35 ms |
| Play command → observed video output, TV | 9 | 10.90 s | 11.44 s |
| Play command → player surface presentation opportunity, TV | 9 | 11.33 s | 11.87 s |
| VLC open → observed video output, TV | 9 | 417 ms | 722 ms |
| Play command → observed video output, movie | 6 | 1.38 s | 1.55 s |
| Play command → player surface presentation opportunity, movie | 6 | 1.51 s | 2.28 s |
| VLC open → observed video output, movie | 6 | 814 ms | 1.11 s |

P95 is the nearest observed rank; with six or nine starts it is effectively the slowest sample, not a reliable estimate of a population tail. Image samples are correlated requests across repeated screens and processes. Timers begin inside the app, not at the physical remote keypress or OS process creation.

The tracked [aggregate evidence](performance/2026-10-04-baseline.json) contains the complete distributions and measurement limits. Private raw traces and screenshots remain under `build/validation/performance-baseline-2026-10-04`, `performance-02`, `performance-03`, and `performance-04`; they are not committed or uploaded.

## What accounts for the wait

Every successful TV start made **117 instrumented HTTP requests**, including **86 ancestry checks**, and fetched the same **22 pages of episodes** before locally filtering to the selected show’s 84 episodes. Movies needed six instrumented HTTP requests and one ancestry check. The count includes the existing automatic bitrate request; SDK metadata/playback-info transactions are measured separately.

The app supplies `SeriesId` to `GET /Items`. The shipped SDK does not define that query parameter. The connected server observer independently checked the installed 12.1.0 OpenAPI schema: `/Items` does not document it; `/Shows/{seriesId}/Episodes` is documented. The 22-page request sequence is consistent with the server ignoring the unsupported filter. The dedicated endpoint has not been behaviorally tested or substituted in this work.

The title screen fetches and validates episodes to show its actions. Pressing Next or Shuffle fetches and validates the episode list again. This repeated work explains why an already loaded show still takes about eleven seconds to start.

The median TV stages were 9.79 seconds for selection, 249 ms for selected-item authorization, 64 ms for controller preparation, 156 ms for provider preparation, and 417 ms from VLC open to observed output. An additional median 466 ms elapsed between the sampled output counter and the player surface marker. Stage medians do not necessarily add to the median total. Excluding the measured selection stage, each paired trial’s remaining time had a median of 1.39 seconds: a useful opportunity estimate, **not a demonstrated optimization result**.

A final launch trace also shows three overlapping complete catalog refreshes. Each issued 163 HTTP requests, including 158 ancestry checks. Two finished after their generation had been superseded. This repeats expensive work even though only the newest result can populate the screen.

All 387 recorded artwork transactions, including cancellations, reported no reused connection. Successful artwork transactions had median pre-request time of 90 ms, first-byte wait of 51 ms and transfer time of 1.4 ms. The existing implementation creates a new ephemeral session for each image and disables its URL cache. A shared scoped image loader is a plausible improvement for repeated browsing, but its payoff is much smaller than the catalog work. UIImage construction is measured separately; construction can defer decoding, so it is not a complete decode-cost measurement.

Local persistence is small in this fixture: median store opening 7.5 ms, loading 1.2 ms and saving 1.7 ms. CloudKit transport is disabled in this simulator; no iCloud performance conclusion follows.

## Server observations and limits

The connected server chat, **Ongoing Maintenance**, ran finite read-only three-second observers during two non-overlapping windows: UTC 00:42:23.985–00:52:23.997 and 00:53:04.274–00:59:04.286 on October 5 (October 4 locally). It reported 320 samples with zero sampler errors, no sampled transcoding, and DirectPlay states. The first captured playback state coincided with a successful movie trial; the second was the failed rendering case below. A DirectPlay session alone is not proof of correct decoded video.

CPU peaks reached roughly 2.7–2.9 cores during catalog/launch periods; sampled DirectPlay CPU was around 2.7–2.9% of one core. This supports investigating API preparation. The cadence misses brief streams and does not count actual starts. Host-wide disk/network counters include other processes, cannot attribute a particular media read, and do not measure seeking latency. The observer’s `/Sessions` calls add a small amount of concurrent server work.

The server observer reported metadata and artwork caches on its internal disk. Cached thumbnails therefore do not have a RAID-seek lower bound. Fresh process launches used warm OS/server/RAID caches: there was no cache purge, disk benchmark, network reconfiguration or server restart. Simulator decode/render performance does not establish physical Apple TV performance.

## Failures retained separately

The initial authentication preflight failed with HTTP 401 and is excluded entirely. Changing the simulator’s application identifier isolated its existing Keychain session. Restoring its original **simulator-only** signing namespace recovered the saved login without retrieving a password. Tracked paid-team configuration remains unchanged; paid provisioning remains deferred.

Discovery trials retained three kinds of failure: an accessibility-order assumption when moving to another card, one show whose episode list was rejected, and one movie with garbled video and no observed decoded-output/advancing-clock evidence. The harness now freezes stable card identities. The rejected show and corrupt movie remain unresolved; they are not successful latency samples. The final benchmark deliberately repeats known working content. Compatibility must be established for these failures before any claim of library-wide reliable playback or retirement of Plex.

All recorded catalog HTTP responses in the accepted baseline were 200. Missing image references and 93 cancelled image tasks are reported separately. Earlier traces overclassified superseded catalog generations as failures; the final instrumentation distinguishes cancellation from failure. Raw span counts are not a server failure rate.

## Proposed next work, in priority order

1. Correct episode-query scope and stop duplicate complete catalog refreshes. Preserve exact account/library binding, metadata filtering and ancestry enforcement. Validate the dedicated episode endpoint’s behavior before using it.
2. Reuse the already checked episode list within the current bound session, while retaining final selected-item authorization and explicit invalidation when account, libraries or catalog generation change. Re-measure both title opening and playback. This targets seconds of user-visible wait; a one-to-two-second warm start is plausible, not yet proven.
3. Add a shared image connection pool and a bounded, identity-scoped image cache for category returns and scrolling. Measure hit/miss behavior, memory use and safe invalidation. Target the approximately 90 ms pre-request budget rather than assume disk tuning will help.
4. Investigate the interval between actual output and the player surface. The existing one-second controller polling is a candidate. Avoid declaring readiness merely because VLC says `playing`: the failed movie demonstrated why real video/clock evidence matters.
5. Only then compare cold/warm trials on physical Apple TV, investigate codec failures, and consider decode/buffering or server/disk tuning if the residual evidence warrants it.

## Instrumentation and reproduction

`--kids-profile` or `KIDS_PROFILE=1` enables JSON-lines and unified-log probes. They are disabled in normal launches. Events contain fixed enums, random trace identities, monotonic elapsed times, wall-clock correlation times, fixed numeric failure/codec categories, and allowlisted numeric measurements. They never serialize URLs, tokens, passwords, titles, paths, headers, payloads or arbitrary error descriptions. Writing/encoding runs on a utility queue with an 8 MiB per-process file cap. Files stay in the app’s local Application Support directory and do not sync through CloudKit.

Probes cover launch, catalog refreshes, policy/ancestry checks, pagination HTTP completion, JSON decode, image HTTP transaction phases, UIImage construction/publication, presentation opportunities, local store operations, selected-item authorization, duplicate metadata fetches, automatic bitrate test, PlaybackInfo, provider preparation, VLC opening/buffering/playing, resume seek, first observed input/decode/output/clock, and player presentation. URLSession phase timings use [Apple’s transaction metrics](https://developer.apple.com/documentation/foundation/urlsessiontasktransactionmetrics). VLC counters are sampled every 50 ms for at most twenty seconds only when profiling is enabled. Counter refresh cadence can add delay; CADisplayLink markers are presentation opportunities, not GPU fences. The launch browse marker uses view appearance, while catalog-ready timing is explicit.

For this saved simulator fixture, build and test with the original simulator identity. Do not copy these overrides into hardware or production signing settings:

```sh
TEST_RUNNER_KIDS_RUN_PROFILE=1 xcodebuild \
  -project Swiftfin.xcodeproj -scheme KidsValidation -configuration Release \
  -destination 'platform=tvOS Simulator,id=C185BD69-BF46-4520-AC7E-8174AEA534E3' \
  -derivedDataPath build/DerivedData -skipMacroValidation \
  DEVELOPMENT_TEAM=FAKETEAMID AppIdentifierPrefix=FAKETEAMID. \
  CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=- \
  -parallel-testing-enabled NO -collect-test-diagnostics never \
  -only-testing:KidsUITests/KidsPerformanceTests \
  -resultBundlePath build/validation/Kids-Performance-NEW.xcresult test

python3 Scripts/Kids/profile.py collect \
  --device C185BD69-BF46-4520-AC7E-8174AEA534E3 \
  --directory build/validation/performance-NEW
python3 -B -m unittest discover -s Scripts/Kids/tests -v
```

Set a destination `start-unix-ms.json` containing `{"after_unix_ms": <start timestamp>}` before the run to exclude older logs. Obtain a full client-state backup before actual playback; retain it. `simulator_resume.py restore` now uses an explicit SDK restoration mode to restore consumed Shuffle entries exactly, with the original binding and a CloudKit-disabled simulator. It never patches SQLite or accesses the server or RAID. Normal production sync retains its monotonic merge behavior.

Validation: 54 native tests passed, eight HTTP-contract tests passed with profiling enabled, five analyzer regression tests passed, two final live playback benchmark methods passed, and both four-launch artwork sweep methods passed. Screenshots and advancing VLC clocks corroborated working playback. Afterward the entire client state, including the original Shuffle bag, matched the backup; the legacy JSON hash was unchanged. The app was relaunched normally without profiling.

`xcrun xctrace` provides a [CLI recording/export path](https://developer.apple.com/documentation/xcode/xcode-command-line-tool-reference), verified locally. No Instruments capture was needed to identify this request-level bottleneck. Use a bounded targeted trace later if unexplained CPU/main-thread/decode gaps remain.
