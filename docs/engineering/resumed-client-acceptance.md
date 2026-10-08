# Resumed client acceptance — 2026-10-08

The source/API/refactor and Swift 6 objectives are complete with current Debug runtime acceptance, verified Release profiling, iOS Release compilation and an observed normal Release launch. Full original state is preserved. Implementation and evidence are included together in the client closeout commit on `feature/kids-release-candidate`; root verifies the remote revision after pushing. Ordered and Shuffle startup were slower than historical measurements; the measured differences and limits are retained below.

The current inventory is 53 extracted libraries, 74 one-way local edges, 664 retained app sources, 252 package source bodies and 15 sources in the pre-existing local targets. Source/API/actor ownership evidence remains in [the completion audit](client-completion-audit.md) and its ledger. Review counts do not establish behavior.

## Accepted runtime and build evidence

| Gate | Current evidence | Result |
| --- | --- | --- |
| Integrated Debug acceptance 89 | Exactly 90 executed/passed methods; zero failures, skips or expected failures | Passed |
| Genuine EOF/next 89 | One executed/passed real method; zero failures/skips | Passed |
| Persisted session cap 89 | One executed/passed real method; zero failures/skips | Passed |
| Release profiles 85 and quiet 86 | Each: two passed methods and seven validated H264 direct-play starts; zero failures/skips/malformed lines | Passed |
| Final tvOS Release build | Optimized `-O`, no `DEBUG`, `ENABLE_TESTABILITY=YES` | Passed |
| iOS Release 36 compile | Zero errors and zero owned Swift/generated-macro diagnostics | Passed; inherited SVGKit-header/lint diagnostics remain separate |
| Accepted compiler-input freeze | All 1,212 hashes unchanged after iOS compilation | Preserved |
| Complete SDK state | Debug 89 and original/restored Release 85/86 exports equal original pre-install session 80 | Preserved |
| Normal Release 86 launch | No arguments; observed Shows/Movies/Parents and approved cards; no autoplay | Passed |
| Source/evidence publication | Included with this client closeout commit on `feature/kids-release-candidate`; root verifies the remote after push | Recorded with implementation |

[Debug results](../../build/validation/resumed-89-results.json) verify the exact 90 + 1 + 1 selection, complete restoration, equality with baseline 80 and unchanged runtime inputs. Acceptance 89 used frozen Debug 88, compiled/installed SHA-256 `74c5bb520b1cef7bcfcd83b3779c950db8c0009c77e69e93229c9b033ab23ffe`.

The retained [approved AVI frame](../../build/validation/avi-89-attachments/E6E5570F-14E0-41A3-828F-B0F65205F73E.png) was inspected and shows readable title-card imagery without the earlier green noise. Passing playback checks separately establish actual frames, advancing time and pause/resume; a still image alone does not establish clock progression.

Release 85 and 86 used SHA-256 `86651095246a5ab2b0966cd67c83f15c7c8c80722b4a814fa61f39a261159317`. All four installed-hash observations in each run matched. Each validated two ordered, one Shuffle and four movie starts. Evidence: [85 build manifest](../../build/validation/performance-release-resumed-85/build-manifest.json), [85 test summary](../../build/validation/performance-release-resumed-85/xcresult-summary.json), [85 restore check](../../build/validation/performance-release-resumed-85/restore-verification.json), [86 build manifest](../../build/validation/performance-release-resumed-86/build-manifest.json), [86 test summary](../../build/validation/performance-release-resumed-86/xcresult-summary.json) and [86 restore check](../../build/validation/performance-release-resumed-86/restore-verification.json).

The [final Release build log](/private/tmp/kids-resumed-tvos-release-84-final.log) and [iOS Release 36 log](/private/tmp/kids-resumed-ios-release-36.log) retain compilation evidence. The Release profile harness excludes `KidsApplicationBoundaryTests.swift`, which uses Debug-only APIs; those fixtures passed in full Debug acceptance 89. The [normal-launch image](../../build/validation/resumed-normal-release-86.png) records the final browser state. All test streams are stopped and no further tests are planned.

## Performance measurements and limits

| First video output | Release 85 | Quiet same-binary Release 86 | Quiet 86 versus historical baseline |
| --- | ---: | ---: | ---: |
| Ordered | 1.842 s | 1.403 s | +27.2%; historical 1.103 s |
| Shuffle | 1.495 s | 1.258 s | +54.2% |
| Movie | 2.009 s | 1.438 s | -0.4% |

The quiet repeat reduced current timings, but ordered and Shuffle retain a raw slowdown relative to historical probe 12. Quiet 86's bandwidth operation was 302.498 ms versus 44.747 ms historically, and transfer was 277.274 ms versus 12.018 ms; time to first byte was similar. The current Mac used Wi-Fi/en1 with inactive Ethernet; the historical route is unknown. Current ancillary catalog work is larger. These small samples do not isolate the cause or establish statistical nonregression, and they do not prove a mechanical disk-seek floor. See [the full Release comparison](../performance/2026-10-08-package-release-comparison.md) for component measurements and scope.

## Repair and retained failures

The mount/layout-before-open gate closes a concrete native scheduling gap. A pure MPEG-4/AVI compatibility policy limits the profile change to qualifying selected sources: the tvOS adapter composes the existing mostCompatible profile for a match and retains current preferences otherwise. The exact approved AVI now plays cleanly through H264 fallback. Target 88 first passed all 22 selected checks with readable output and complete SDK restoration; full 89 then passed the current selection above.

Adjacent evidence comprises 21 mount-gate owner tests, 11 numeric/privacy checks, 13 strict harness-verifier tests and six pure compatibility-policy tests covering 49 inputs. Read-only server FFmpeg checks decoded clean five- and fourteen-second prefixes; an HTTP 4,096-byte prefix matched the approved source. Existing restricted-account transcoding permission and internal paths were verified under RAID write denial. Whole-file health and library-wide codec support are not established by these bounded checks.

| Earlier attempt | Retained outcome |
| --- | --- |
| Cancelled acceptance 79 | Remains cancelled |
| Resumed 80 | 80 of 81 integrated methods passed; AVI startup failed. Separate EOF/next and cap passed; complete SDK state restored equal. |
| Target 81 | AVI mechanical checks passed; one UIKit window fixture failed, and AVI output showed green noise. |
| Target 83 | Repaired UIKit fixture and all 22 selected checks passed mechanically; AVI output remained visually bad. |
| Targets 85, 86 and 87 | Forced-avcodec, no-direct-render and legacy-display trials each passed all 22 selected checks mechanically but failed visual inspection. All unsuccessful trial flags were removed. |
| First Release 84 build | Failed because @testable imports lacked enable-testing. Final optimized build passed with testability enabled. |
| Release profile 84 | Aborted when the installed executable was the old Debug binary; complete state restored to baseline 80 before verified Release profiles. |

Targets 81, 83, 85, 86 and 87 each restored complete SDK state equal. Earlier failures remain separate from accepted 88/89 and Release 85/86 results. The [runtime completion plan](runtime-completion-plan.md) preserves finite, acyclic dependency graphs and the repair sequence.

Physical Apple TV installation/playback, live CloudKit transport, server boot/reboot acceptance and App Store upload/release remain explicitly deferred or separately owned. Every RAID media file remains immutable. Only root builds, uses the shared simulator, integrates code or commits; parallel agents retain disjoint responsibilities. Implementation and evidence are included together in the client closeout commit on `feature/kids-release-candidate`; root verifies the remote revision after pushing.
