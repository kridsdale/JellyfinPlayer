# Package candidate Release comparison — 2026-10-08

Both Release 85 and the single quiet same-binary Release 86 repeat passed the exact two profiling methods and seven H264 direct-play starts. Ordered/Shuffle and bandwidth-probe timing increases persisted in 86. The movie median returned to the historical value, with one slower outlier. Functional acceptance passed; unchanged timing, a causal regression or a speedup is not established.

The candidate executable is SHA256 `86651095246a5ab2b0966cd67c83f15c7c8c80722b4a814fa61f39a261159317`, built from the package worktree based on `d431ccf1a534c90fb8a2b1f384b6663b1937f960`. Both runs verified explicit preinstall, both method starts and the post-test hash. The app compiler invocation uses `-O` and `-enable-testing` without `DEBUG` ([compiler evidence](/private/tmp/kids-resumed-tvos-release-84-retry.log:10632)). The final incremental Release build-for-testing passed with zero errors ([build evidence](/private/tmp/kids-resumed-tvos-release-84-final.log:5143)); `ENABLE_TESTABILITY=YES` permits package test imports. `KidsApplicationBoundaryTests.swift`, which uses DEBUG-only preview APIs, was excluded from the Release test build and separately passed in Debug acceptance 89.

| Run | Passed / failed / skipped methods | Validated ordered / Shuffle / movie | Files / events / malformed | Full SDK state |
|---|---|---|---|---|
| Release 85 | 2 / 0 / 0 | 2 / 1 / 4 | 2 / 4,701 / 0 | Original85 = restored85 = original80 |
| Quiet Release 86 | 2 / 0 / 0 | 2 / 1 / 4 | 2 / 5,099 / 0 | Original86 = restored86 = original80 |

Evidence: [85 aggregate](../../build/validation/performance-release-resumed-85/summary.json), [85 test summary](../../build/validation/performance-release-resumed-85/xcresult-summary.json), [85 build manifest](../../build/validation/performance-release-resumed-85/build-manifest.json), [86 aggregate](../../build/validation/performance-release-resumed-86/summary.json), [86 test summary](../../build/validation/performance-release-resumed-86/xcresult-summary.json), [86 build manifest](../../build/validation/performance-release-resumed-86/build-manifest.json). Restore checks are retained alongside each aggregate. 86 ran after client builds ended, without a concurrent observer, cache purge, source change or server configuration change.

Selectors match [probe 12](2026-10-05-swift6-final-12.json): `testProfileEpisodeAndShuffleStarts` and `testProfileMovieStarts`. Each run has two launches, seven starts and 29 grid presentations: 7 memory hits and 22 network loads, with another 2 title memory hits. Movie/ordered/Shuffle codec, dimensions, bit depth, frame rate and declared bitrate match. Initial resumed positions match; later checkpoints drift slightly. Every start retains fresh authorization, one ancestry request and six instrumented HTTP requests. Ancillary work differs across historical/85/86: HTTP 200 transactions 515/636/702, ancestry 445/561/627 and episode-list 1/2/2. AVI compatibility playback is separate.

Values below are medians in milliseconds; change compares 86 with historical. Full ranges, sample P95 values and 85/86 deltas are retained in the [comparison JSON](2026-10-08-package-release-comparison.json). The small runs remain separate.

| Measurement | n each | Probe 12 | Release 85 | Quiet 86 | 86 change |
|---|---:|---:|---:|---:|---:|
| First Shows ready | 2 | 1067.635 | 1032.995 | 1259.648 | +192.013 (+18.0%) |
| First browse | 2 | 1107.161 | 1076.669 | 1304.508 | +197.347 (+17.8%) |
| Complete catalog | 2 | 3185.383 | 2111.679 | 1971.358 | -1214.025 (-38.1%) |
| Grid artwork | 29 | 123.572 | 145.174 | 111.558 | -12.014 (-9.7%) |
| Grid artwork: memory | 7 | 19.857 | 26.861 | 45.157 | +25.300 (+127.4%) |
| Grid artwork: network | 22 | 192.355 | 351.931 | 210.071 | +17.716 (+9.2%) |
| Ordered output | 2 | 1102.900 | 1841.819 | 1402.794 | +299.894 (+27.2%) |
| Shuffle output | 1 | 815.898 | 1495.227 | 1258.372 | +442.474 (+54.2%) |
| Movie output | 4 | 1443.907 | 2008.825 | 1438.417 | -5.490 (-0.4%) |
| Ordered surface | 2 | 1398.752 | 2148.142 | 1614.910 | +216.158 (+15.5%) |
| Shuffle surface | 1 | 1082.019 | 1631.607 | 1532.263 | +450.244 (+41.6%) |
| Movie surface | 4 | 1524.761 | 2505.990 | 1756.276 | +231.515 (+15.2%) |
| Bandwidth operation | 7 | 44.747 | 588.436 | 302.498 | +257.751 (+576.0%) |
| Native drain | 7 | 64.858 | 62.140 | 52.718 | -12.140 (-18.7%) |

Every bandwidth sample still requested 5,000,000 bytes and received 8,388,608 Data/network bytes. In 86, bandwidth operation median was 302.498 ms (+257.751 ms historical); URLSession transfer median 277.274 ms versus 12.018 ms (+265.256 ms), first-byte 28.776 versus 29.336 ms, and pre-request 0.501 versus 0.541 ms. The measured repeated 8 MiB transfer remains an investigation target. It does not establish whether network/server conditions or client behavior caused the added time, or justify a cache/source change without further proof.

Provider medians in 86 were ordered 399.315/movie 374.664 ms versus historical 135.300/117.664 ms. Native open-to-output was ordered 609.826 versus 392.420 ms and movie 765.111 versus 784.996 ms. Movie output-to-surface was 319.639 versus 148.745 ms. The seven linked per-start rows below show the probe occupies 184.227–344.290 ms of 267.507–455.939 ms provider work. These trace-linked durations are observations; independently calculated metric medians cannot be added into causal attribution.

| Quiet 86 start | Resume s | Provider ms | Probe ms | Native open→output ms | Output ms | Surface ms |
|---|---:|---:|---:|---:|---:|---:|
| movie 1 | 181.405 | 455.939 | 344.290 | 794.964 | 1439.135 | 1997.220 |
| movie 2 | 184.257 | 359.399 | 184.227 | 577.242 | 1393.355 | 1515.333 |
| movie 3 | 187.379 | 267.507 | 203.125 | 735.258 | 1437.699 | 1480.896 |
| movie 4 | 190.218 | 389.930 | 329.234 | 1683.600 | 2546.529 | 3063.828 |
| ordered 1 | 113.694 | 434.191 | 334.681 | 692.910 | 1357.015 | 1615.063 |
| ordered 2 | 116.798 | 364.438 | 302.498 | 526.742 | 1448.573 | 1614.757 |
| shuffle 1 | 0.000 | 308.782 | 256.769 | 475.814 | 1258.372 | 1532.263 |

The fourth 86 movie start accounts for the 2,546.529 ms maximum: its native open-to-output interval was 1,683.600 ms, with all resume checks ultimately satisfied. Historical movie maximum was 1,720.999 ms. Overall 86 grid-artwork median/P95 improved to 111.558/259.539 ms from 123.572/315.298 ms, while network-grid median was 210.071 versus 192.355 ms and memory-grid median 45.157 versus 19.857 ms. Shows/browse medians were approximately 18% higher; catalog completion and drain were lower. These mixed changes do not establish a general performance improvement.

Release 85 has two known startup catalog markers at line 3, elapsed 0.130958/0.133625 ms. 86 has two line 3 markers elapsed 0.146292/0.156584 ms and an additional line 5 marker elapsed 0.079333 ms in `671BE9BB…jsonl`. All have unknown variant/empty values and end before HTTP; the extra marker follows the first by 53.707 ms. Successful Shows/Movies/overall catalog completion follows. They match the early account/binding readiness pattern, but the exact unavailable guard condition is not exposed; they are not test failures or intentional HTTP/preview fixture outcomes. Neither run has playback, artwork, report, audio or drain failure outcomes. Each retains one episode-cache/prefetch cancellation and incomplete ancestry/catalog/HTTP/launch spans, with no incomplete playback span.

The bounded [network context](../../build/validation/resumed-network-context.json) was observed after 85 and before 86. The current route uses active Wi-Fi/en1/MTU 1500; built-in Ethernet/en0 is inactive, with zero interface error/collision counters. The October 5 route is unknown. The server snapshot showed one Jellyfin process near 1.2% CPU, 95% CPU idle, no active playback or FFmpeg process and low disk activity; it showed no ongoing saturation or leftover transcoder then. The reported server 10G link targeted the previous client address and does not establish current end-to-end capacity. These snapshots cannot explain earlier timing changes or rule out transient costs during 86. No network settings, services or media were changed.

No caches were purged, no mechanical seek floor was isolated, and these simulator sample sizes do not establish sustained playback percentiles or physical-device performance. Displayed-picture readiness is sampled; a surface marker is a run-loop presentation opportunity, not a GPU fence. Release 84 aborted on an installed Debug binary mismatch and remains retained; 85 and 86 are explicitly installed, hash-verified replacements. The finite comparison is complete: functional acceptance passed, ordered/Shuffle and probe slowdowns persisted, and no statistical or causal regression claim is made.
