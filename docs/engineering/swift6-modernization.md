# Swift 6 ownership modernization

This pass makes UI, saved-account, playback, and observation ownership explicit before extracting the remaining monolith into Swift packages. It changes only the app targets' language setting; dependencies keep their declared package language modes. The default actor isolation remains `nonisolated`, with explicit `@MainActor` declarations for UI and session work.

## Changes

- Saved user sessions, their factories, login/PIN callbacks, route content, gesture coordinators, preview image providers, and dynamic user-specific playback profiles are owned by the main actor. Pure identity hashing and immutable defaults remain usable outside it.
- Isolated protocol conformances retain the actor boundary where a legacy library or supplement holds a UI view model. A short-lived actor-owned refresh batch preserves parallel library refresh without transferring those existential values to child tasks.
- The settings override table stores immutable Swift values in `Synchronization.Mutex`. Foundation bridging happens after lookup, so an arbitrary mutable `Any` is never shared by the table. The one existing continuation-resumption lock has a narrowly documented `@unchecked Sendable` conformance; the lock protects its only mutable field.
- `PokeIntervalTimer` uses a cancellable one-shot task with a weak owner. Replacement, Stop, delivery, and destruction occur on the same actor. A pending deadline no longer retains the dismissed player or toast through a dispatch-work-item cycle.
- Stored-value observation inherits its owner's actor. SQL observation announces changes to the existing store instead of decoding and writing an observed value back into it.
- Artwork prefetch crosses child tasks using a Sendable model reference and immutable item metadata; image creation stays on the model's actor.
- Status screen actions use explicit `action:` labels. Swift 6 forward matching bound an ambiguous trailing closure to the optional parent callback, displaying a spinner and Parents button instead of Retry. The remote recovery regression caught this real UI behavior; failed trials are retained. The additional assertion now tests the visible, usable Retry control instead of absence of a parent button in the underlying browse toolbar. All status-action call sites now name the intended callback.
- The iOS Release identifier and Spotlight application identity now use `com.kridsdale.JellyfinPlayer` and the configured KidsJellyFin display name.

System remote commands copy only immutable event values into a main-actor task and reject obsolete audio leases. AVPlayer observations and seek completions cross to the actor and reject replaced playback generations; delayed transport work is cancelled on dismissal. These SDK paths compile, but the kids simulator stream uses VLC rather than establishing full AVPlayer behavior.

These changes do not relax account/library authorization, add media, prefetch full video, migrate the storage schema, or write to the server's RAID.

## Verification

`sh Scripts/Kids/test_runtime.sh` compiles the actual production utilities in Swift 6 on macOS and exercises their behavior:

- Boolean/string/integer/double overrides and conversions, removal, preservation of underlying saved values, and 64 concurrent independent writers performing 6,400 updates.
- Replacement of pending deadlines, Stop and reuse, actor-isolated delivery, releasing an owner with a pending 60-second timer while retaining its subscriber, and subscriber cancellation.
- Bitrate calculation from the actual received payload and monotonic fractional duration, lower/upper bounds and rejection of empty or invalid measurements. This replaces wall-clock timing and an assumption that requested bytes equal returned bytes; it adds no request or cache.

The tvOS Debug app build with `KIDS_SWIFT_LANGUAGE_VERSION=6` passed in `/private/tmp/kids-swift6-explicit-14.log`. The latest iOS Release build passed for both arm64 and x86_64 in `/private/tmp/kids-swift6-ios-release-06.log`, including the SDK callback ownership and bandwidth-measurement changes. The shared app configuration now selects Swift 6. The first real acceptance run failed: synchronous legacy `@Function` handlers executed off the main actor after StatefulMacro erased closure isolation in its registry. Pause/play then trapped in main-actor Combine consumers. App handlers now use an explicit asynchronous method boundary and actor preconditions, so generated `await` calls hop to the owner before accessing state. All nine synchronous app handlers were covered, including connection monitoring and sign-in. No dependency checkout is patched. The combined build compiled and passed 21 of 22 acceptance checks: all 16 navigation checks and five real-account playback methods. Its failed-stream Retry kept the right item but lost the initial checkpoint because the controller had not initialized its displayed time before a failed open. The controller now retains the requested position until an accepted native clock exists. The failed result is retained in `Kids-Swift6-Acceptance-05.xcresult`; the repaired exact-item/checkpoint Retry passed in `Kids-Swift6-Recovery-06.xcresult` (48.059 s). Genuine EOF/countdown/next playback passed in `Kids-Swift6-Natural-07.xcresult` (60.716 s); the genuine second EOF stopped at the persisted cap in `Kids-Swift6-Session-Cap-08.xcresult` (47.425 s). The complete original simulator progress was restored through the SwiftData SDK and compared equal. These are separate results, not one all-green combined run. The final native package rerun passed 69 core/HTTP tests plus 23 persistence tests; the profiling analyzer passed ten tests and App Store metadata tooling passed six. Runtime helper suites passed against actual production code.

An independent, finite server observer captured 239 samples with zero errors. The same anonymous restricted-account session remained present across six consecutive empty NowPlaying samples between two approved H264/AAC streams, then three empty samples after the second stream. All 30 sampled active states were DirectPlay; maximum concurrency was one. A large forward position jump is recorded separately and is not proof of continuous playback. The client tests establish actual frames, clocks and EOF behavior; server sampling corroborates session cleanup. RAID write denial was checked at both ends and the observer logged out. No server configuration or media files changed.

## Compatibility and deferred acceptance

The build retains existing compatibility annotations for third-party SDKs. Remaining inherited Binding, macro, UserDefaults, HostingController, and SDK isolation warnings require separate review; a successful Swift 6 build does not mean the entire dependency graph is free of concurrency warnings.

Apple accepted the team API key, but no physical tvOS device was available for the development profile. The human explicitly deferred physical-device installation and live CloudKit transport testing. Local SwiftData tests, ad-hoc simulator signing, and selecting the paid team do not establish signed-device or cross-device iCloud success.

The next goal remains the [Swift package responsibility refactor](next-goal.md), after the current engineering work finishes.
