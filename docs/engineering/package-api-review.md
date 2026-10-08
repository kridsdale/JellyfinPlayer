# Package API review

This is the current scoped source/API checkpoint, not whole-client acceptance. Exact source, manifest and compiler-graph hashes are in source-review-ledger.json. Compiler symbol graphs include external type extensions and protocol witnesses; they locate the emitted surface and do not prove behavior.

## Reviewed batch (2026-10-07)

| Module | Complete source bodies | Emitted public symbols |
| --- | ---: | ---: |
| SwiftfinCollections | 9 | 59 |
| SwiftfinFilters | 11 | 102 |
| SwiftfinAccountModels | 8 | 89 |
| SwiftfinAsyncStreams | 7 | 38 |

All generic collection helpers execute synchronously and retain no callbacks. Arbitrary element/reference types do not acquire Sendable semantics. ArrayBuilder public methods are compiler entrypoints. The unused mutable Trie and its sole test were removed. Dictionary unique-key preconditions and existing optional projection behavior remain explicit.

Filter Codable/raw identities and query selection semantics remain unchanged. The only removed year API forced an Int conversion and had no production caller. The query owner captures one user/transport and validates around modern/legacy requests and publication.

Account records, connection/context/draft values, selectors, deep links and access-policy strings contain no native handles or implicit hardware/credential queries. Parsing or selecting a record does not authorize it. Actual local storage, credential access and session effects remain in their owners.

The async owner provides generations, scoped delivery and serialized reporting through explicit checked callbacks/values. Both report consumers retain their original client. Natural stream completion is terminal for one publisher, while subscription cancellation allows a fresh source; the new regression verifies that completion cannot revive an old source. Request and callback guards cannot undo effects already committed by noncooperating consumers.

## Validation and limits

Collections: 10 native tests. Filters: 12. AsyncStreams: 62, including the added completion regression. These are synthetic offline tests. The unchanged account-model native suite is not rerun or counted as new acceptance.

The tvOS test host compiles with build-for-testing; iOS Release compiles. Neither command installs, launches or executes a simulator. All 53 package boundaries pass. The first Filters symbol extraction failed because its C dependency module maps were omitted; extraction succeeds using the existing built dependency headers/maps. No dependency source was changed.

The ledger now records 103 scoped interfaces among 250 current package sources. The four modules have complete source/public-declaration review; caller evidence is explicitly scoped. Remaining source/API/consumer coverage and final whole-graph navigation/playback acceptance are still required. The human runtime hold remains in force. SDK pins, paid-team/schema configuration, saved SDK progress and the five protected tracked inputs remain unchanged. No server or RAID action occurred.


## Value, platform and presentation batch (2026-10-07)

Text exports now confine server-provided titles to one filename component. The original temporary-file escape regression failed before the fix and passes afterward. Text and UIState pass 42 native contracts, including two new export regressions; the unused inverse binding is removed. Seven additional complete module source bodies and public declaration surfaces are reviewed with scoped consumers. tvOS Debug and iOS Release compile without owned Swift/generated-macro diagnostics. The graph remains 53 libraries with all 664 app sources classified and 133 scoped interface entries among 250 package sources. Remaining graph review and held runtime acceptance are required; items 1/2 stay active.

| Module | Complete source bodies | macOS public symbols |
| --- | ---: | ---: |
| SwiftfinValues | 4 | 8 |
| SwiftfinText | 2 | 39 |
| SwiftfinFormatting | 5 | 71 |
| SwiftfinPermissions | 5 | 15 |
| SwiftfinMediaTracks | 7 | 56 |
| SwiftfinNowPlaying | 4 | 48 |
| SwiftfinUIState | 11 | 60 |

UIKit-only NowPlayingArtwork was read directly and compiles in both app targets; it is absent from the macOS graph. Public numerical helpers retain normal representability/nonzero-divisor preconditions. Formatters use presentation clock/calendar/locale and locally created native formatters. UI wrappers own actor-confined values rather than claiming arbitrary elements are Sendable. Permission driver/reply bodies were read without invoking native capability checks or prompts. Media-track policy remains a captured value decision; no player handle or request work moves into it. Now Playing native publication and command delivery remain held.

The file-effect regression uses a generated temporary workspace containing an export directory and a sibling sentinel. Before repair the title ../sentinel replaced that sibling; afterward the sibling is unchanged and the export remains inside its chosen directory. Separate coverage verifies slash, absolute-looking title, NUL, Unicode and literal percent sequences; existing UTF8/empty/atomic replacement/failure fixtures still pass. No household file or RAID path is used by these tests.
