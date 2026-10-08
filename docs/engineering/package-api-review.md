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


## Transport, playback profiles and generic catalog (2026-10-07)

Socket subscription now survives synchronous callback retirement without a Swift exclusivity crash, and transport factories cannot overwrite a newer cache binding. Four new test declarations exercise six stop/replacement cases; all 46 networking contracts pass. PlaybackProfiles, Networking and MediaCatalog complete source/public declaration reviews add 42 source bodies with scoped consumers. tvOS Debug and iOS Release compile without owned Swift/generated-macro diagnostics. The graph remains 53 libraries with all 664 app sources classified and 168 scoped interface entries covering 166 of 250 package sources. Remaining graph review and held runtime acceptance are required; items 1/2 stay active.

| Module | Complete source bodies | macOS public symbols |
| --- | ---: | ---: |
| SwiftfinPlaybackProfiles | 28 | 253 |
| SwiftfinNetworking | 6 | 86 |
| SwiftfinMediaCatalog | 8 | 178 |

The before-fix fake-driver run terminated with a Swift exclusivity conflict when native subscription synchronously stopped the controller. Separate factory-reentry cache cases produced three failed expectations. Retirement now detaches the old worker, wake stream, native driver and leases before invoking callbacks; generation and driver identity reject stale source/lease publication, including replacement initiated during disconnect. Both socket and account cache public signatures remain unchanged.

Profile tables/builders are pure policy over captured settings/capability values; app composition owns localization, stored settings and hardware snapshots. Generic catalog policy preserves read requests and account checks; it does not replace the child catalog authorization boundary. SDK construction, discovery and native callbacks were read as source; no discovery, hardware, credential or permission query was executed. Compiler symbols are interface evidence, not runtime proof. Simulator/server activity and final whole-graph acceptance remain held.


## Child domain, catalog, artwork and playback policy (2026-10-07)

Transport callback reentry fixes are published as 7c5ad9bf; 46 networking contracts and both compile gates pass. Complete child domain/catalog/artwork/playback policy review adds ten unchanged source bodies and four compiler public interfaces. The graph remains 53 libraries; 18 complete module reviews cover 125 source bodies, and 177 scoped interface entries cover 175 unique sources of 250. All 664 app sources remain classified. Scoped call-site review is not complete consumer acceptance. Remaining whole-graph review and held runtime acceptance are required; items 1/2 stay active.

| Module | Complete source bodies | macOS public symbols |
| --- | ---: | ---: |
| KidsDomain | 2 | 123 |
| KidsCatalog | 2 | 31 |
| KidsArtwork | 2 | 11 |
| KidsPlayback | 4 | 13 |

Catalog publication requires exact account/library preflight and per-item ancestry. Episode metadata and artwork pools bind the exact account/libraries, reject invalid values and retired generations, and do not authorize playback. Upper-layer scoped reads confirm only displayed verified rows reach artwork and native readiness requires pictures plus a post-resume clock. Child domain retains shuffle reservations, parent cursor retirement, session counts and explicit numbering review. All four modules and compiler inputs are unchanged; prior compile/native evidence is reused, and no new execution result is claimed. KidsAppModel source was inspected only at these call sites, so its complete review remains outstanding.


## Storage, settings, secure accounts and progress (2026-10-07)

Local security edits now reject retirement during credential verification/effects and nested commits before further settings publication. Four new regressions reproduce eleven failures before repair; all 53 account-store contracts pass afterward. tvOS Debug and iOS Release compile without owned Swift/generated-macro diagnostics. Seven complete storage/account module reviews add 35 source bodies. The graph remains 53 libraries; 25 complete module reviews cover 160 source bodies, and 199 scoped interface entries cover 197 unique sources of 250. All 664 app sources remain classified. Remaining whole-graph/consumer review and held runtime acceptance are required; items 1/2 stay active.

| Module | Complete source bodies | macOS public symbols |
| --- | ---: | ---: |
| SwiftfinStorage | 15 | 40 |
| SwiftfinStoredValues | 4 | 18 |
| SwiftfinStoredValuesUI | 1 | 6 |
| SwiftfinCredentials | 3 | 21 |
| SwiftfinAccountStore | 6 | 71 |
| KidsAccounts | 4 | 48 |
| KidsPersistence | 2 | 58 |

The production security view model captures its original session and transport in the editor checkpoint. Before repair, fake credential callbacks could retire that checkpoint yet publish verification success, mutate policy/hint, or reenter a second commit. The repaired owner checks after reads/effects and between settings writes, rejects nested operations and retains retry after credential failure. A credential already accepted before retirement remains accepted; no rollback or cross-store transaction is claimed. Existing direct-store ordering and public signatures stay unchanged.

Native database objects and Security dictionaries stay internal. Typed settings preserve installed keys and raw/JSON representations. Source-only exports omitted by symbol graphs were read directly; SwiftData generated model interoperability declarations were also reviewed. Existing schema version locks, CloudKit model/container, credential attributes, signing and saved progress are unchanged. The native tests use injected in-memory credentials, generated UUID defaults suites and temporary SQLite stores. No real credential query, actual cloud transport, simulator/server activity or RAID operation occurred.
