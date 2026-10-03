# Kids implementation validation record

Status: implementation and local validation in progress; **not yet a release candidate**. Updated 2026-10-03. Branch: `feature/kids-release-candidate`.

## Verified

- `swift test --package-path KidsCore`: 26 domain/HTTP tests pass, including damaged local state, immutable binding, policy and ancestry rejection, progress/Shuffle independence, session counting and persistence.
- Apple TV 4K (3rd generation), tvOS 27.0, Xcode 27, signed Debug build: the full current `KidsValidation` suite passed **15 remote UI tests, zero failures**, in 146.4 seconds; two opt-in live tests were skipped. The result bundle is `build/validation/Kids-Checkpoint-21.xcresult`.
- The suite drives show/title/Back focus, Movies return, one movie Resume action, ordered Again, masked parent PIN, native keyboard submission, unlock/relock, independently focused Set Next, preservation of another show's progress, movie Start over after the current player's stop checkpoint, empty category, denial clearing a prior catalog, exact-item recovery navigation, paused timeline seek, countdown cancellation/session end, scrolled-card return focus, and access to protected Parents from the offline screen.
- Retained checkpoint-21 screenshots were exported for visual review, including offline protected help, scrolled-card focus restoration with clipped grid content, the initial grid, and the show title. The focused parent action has readable contrast; the movie Resume label is complete; explicit Start over returns the movie to Play. The fixtures use the production views and local progress methods but do not open a video stream or authenticate a real account.
- Signed **Release simulator build passed** after the final source changes. `codesign --verify --deep --strict` succeeded; the executable has no `KidsPreviewFixtures` model symbols or `--kids-preview=` launch string. An actual current Release launch with that Debug argument showed the neutral parent-setup screen, with no synthetic catalog. Screenshot: `build/validation/kids-release-neutral.png`. This verifies simulator Release behavior, not physical-device signing or playback.
- The current **Release device build for generic tvOS passed** with signing disabled, targeting arm64 Apple TV hardware. This establishes device compilation, not installation or physical-device playback.
- `KidsLivePlaybackTests` compiles against the real simulator runner and is disabled by default. Its two skipped tests are not playback passes. When enabled after restricted-account setup, it launches without preview arguments and checks episode/movie time progression, pause/resume, 15-second seeking, and ordered resume after relaunch. Natural transition and server corroboration still need separate evidence.
- 1531Server read-only probe on 2026-10-03 confirmed `/Items/{id}/Ancestors` returns the approved root ID for a series, regular episode, and movie. The server also checked the sampled paths against its internal curated allowlist. This used the existing player identity and admin-authenticated metadata access; it does not prove restricted-account isolation.

## Required before release-candidate evaluation

- Provision and verify the dedicated `kidsplayer` account with only the two existing approved libraries and no admin/deletion permissions. The server chat has staged the proposal but cannot retrieve the driver's human approval. It clarified that separate approval specifically in that chat is not required; verifiable authorization remains pending. Its old-PIN comparison is now optional; independently generated credentials no longer require the legacy secret. The account and private credential file are absent.
- Use the actual restricted account to play a kids' episode and movie, observe time/frames, pause/resume and seek, kill/relaunch, and complete an episode-to-next transition; obtain server corroboration.
- Exercise exact-item reconnect, unavailable server, revoked/expired token, account/library change, old-artwork isolation, repeated Select and return-focus behavior. Keep synthetic denied IDs out of child-facing screenshots.
- Complete the P0 matrix and mark each required gate with current evidence before changing this status.

## Local code review

- Reproduced an ordered-progress bug: Set Next to the currently playing episode reset its position, then an old stream checkpoint restored the old position. The new regression failed before the fix and passes afterward. Retired ordered sessions no longer overwrite that parent choice; retired player controls also ignore toggle/seek events.
- A new browse visit refreshes the verified catalog and restores the selected card and scroll position. Reinsertion after that refresh does not trigger a refresh loop. The remote fixture test verifies scrolled focus; actual server additions still require live integration.

- Delayed parent-episode and playback-start responses are discarded after refresh or identity changes. Parent-episode authorization failures use the same neutral catalog-clearing path as other denied requests. These paths are implemented and reviewed; actual token/identity-change integration evidence remains required below.
- All generated app, test, and checkpoint artifacts are on the local internal APFS data volume; `KidsCore/.build` and `build/` are ignored. No server library/media operation was performed by this client work.

## Scope

The earlier `build/validation/SIMULATOR-VALIDATION.md` establishes the upstream playback foundation only. It does not prove this kids implementation. All local builds/test results stay under ignored `build/`. No RAID file or catalog changes are part of client validation.

Physical Apple TV audio/HDR/formats, sleep/wake, signing/TestFlight installation, child observation and the one-week family pilot remain user evaluation activities following a simulator candidate. Unattended server startup and Plex retirement are not claimed here.
