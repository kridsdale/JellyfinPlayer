# Active goal: libraries with minimal responsibilities

Requested by the user on 2026-10-05 and initially queued. It is now the active full-client/package and Swift 6 workstream. See current-goal-status.md and package-refactor.md for current evidence; the complete objective and criteria below remain required.

## Objective

Refactor the client into logically minimal Swift package libraries, with clear ownership, small public APIs and one-way dependencies. Keep the app target as the composition and platform UI layer. Preserve child navigation, exact account/library authorization, playback and recovery, local/CloudKit progress behavior, performance measurements and immutable RAID media.

## Completion criteria

- Map current responsibilities and dependency edges from source before choosing package boundaries.
- Propose practical boundaries around domain behavior, curated catalog access, persistence/sync, playback lifecycle/reporting, artwork and diagnostics; merge or split only where actual dependencies justify it.
- Move one responsibility at a time, keep tests near their libraries and enforce API/actor isolation under Swift 6.
- Keep Jellyfin SDK and native-player implementations behind the interfaces that own them; avoid a catch-all shared package or a package for every file.
- Verify simulator navigation and real restricted-account playback after each meaningful integration change. Retain signing, iCloud entitlement and performance evidence.
- Document the package dependency graph, public interfaces, composition root and extension path.

Apple TV/cloud and server acceptance dependencies remain explicit and deferred or separately tracked; they are not declared complete by starting or validating this refactor.
