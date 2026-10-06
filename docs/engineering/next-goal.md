# Next goal: libraries with minimal responsibilities

Requested by the user on 2026-10-05. Start only after the active engineering goal is complete; this is a queued follow-up, not a replacement for current work.

## Objective

Refactor the client into logically minimal Swift package libraries, with clear ownership, small public APIs and one-way dependencies. Keep the app target as the composition and platform UI layer. Preserve child navigation, exact account/library authorization, playback and recovery, local/CloudKit progress behavior, performance measurements and immutable RAID media.

## Completion criteria

- Map current responsibilities and dependency edges from source before choosing package boundaries.
- Propose practical boundaries around domain behavior, curated catalog access, persistence/sync, playback lifecycle/reporting, artwork and diagnostics; merge or split only where actual dependencies justify it.
- Move one responsibility at a time, keep tests near their libraries and enforce API/actor isolation under Swift 6.
- Keep Jellyfin SDK and native-player implementations behind the interfaces that own them; avoid a catch-all shared package or a package for every file.
- Verify simulator navigation and real restricted-account playback after each meaningful integration change. Retain signing, iCloud entitlement and performance evidence.
- Document the package dependency graph, public interfaces, composition root and extension path.

Do not begin the refactor while the preceding active goal still has required work. Apple TV/cloud and server acceptance dependencies must remain explicit rather than being declared complete to start this goal.
